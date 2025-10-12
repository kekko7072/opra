import Foundation
import AVFoundation
import Speech

@MainActor class TextToSpeechManager: NSObject, ObservableObject {
    @Published var isSpeaking: Bool = false
    @Published var isPaused: Bool = false
    @Published var speechRate: Float = 0.5
    @Published var currentVoice: AVSpeechSynthesisVoice?
    @Published var readingProgress: Double = 0.0
    @Published var currentWordIndex: Int = 0
    @Published var totalWords: Int = 0
    @Published var isPersonalVoiceAuthorized: Bool = false
    @Published var personalVoiceStatus: String = "Not requested"
    @Published var enableSSML: Bool = false
    
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var settingsManager: SettingsManager?
    private var fullText: String = ""
    private var words: [String] = []
    private var progressTimer: DispatchSourceTimer?
    private var utteranceStartDate: Date?
    private var pausedTime: TimeInterval = 0.0
    private var totalPausedTime: TimeInterval = 0.0
    private var timeoutTimer: DispatchSourceTimer?
    
    // Chunking support
    private var isChunked: Bool = false
    private var chunkedTexts: [String] = []
    private var currentChunk: Int = 0
    private var totalChunks: Int = 0
    private var chunkCompletionHandler: (() -> Void)?
    private var pdfExtractor: PDFTextExtractor?
    
    override init() {
        super.init()
        synthesizer.delegate = self
        setupDefaultVoice()
        checkPersonalVoiceAuthorization()
    }
    
    func setSettingsManager(_ settings: SettingsManager) {
        settingsManager = settings
        speechRate = settings.speechRate
        speechRate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, speechRate))
        if let voice = settings.getSelectedVoice() {
            currentVoice = voice
        }
    }
    
    func setPDFExtractor(_ extractor: PDFTextExtractor) {
        pdfExtractor = extractor
    }
    
    private func setupDefaultVoice() {
        // Try to get a high-quality English voice
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            currentVoice = voice
        } else if let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("en") }) {
            currentVoice = voice
        } else {
            currentVoice = AVSpeechSynthesisVoice.speechVoices().first
        }
    }
    
    func speak(_ text: String) {
        speak(text, chunkCompletionHandler: nil)
    }
    
    func speak(_ text: String, chunkCompletionHandler: (() -> Void)?) {
        // Store chunk completion handler BEFORE stopping speech
        self.chunkCompletionHandler = chunkCompletionHandler
        print("Set chunk completion handler: \(chunkCompletionHandler != nil)")
        
        // Stop any current speech and tracking first on the main actor
        stopSpeaking()
        
        // Add a longer delay to ensure audio system is fully ready and previous utterance is cleared
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.performSpeak(text, chunkCompletionHandler: chunkCompletionHandler)
        }
    }
    
    private func performSpeak(_ text: String, chunkCompletionHandler: (() -> Void)?) {
        // Validate input text quickly on main
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("Warning: Attempting to speak empty text")
            return
        }

        // Preprocess off the main thread to avoid blocking UI
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let processedText = self.preprocessTextForTTS(trimmed)

            // Validate processed text
            guard !processedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("Warning: Processed text is empty after preprocessing")
                return
            }

            // Switch back to the main actor to interact with AVSpeechSynthesizer and published properties
            await MainActor.run {
                self.fullText = processedText
                self.words = processedText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                self.totalWords = self.words.count
                self.currentWordIndex = 0
                self.readingProgress = 0.0
                self.pausedTime = 0.0
                self.totalPausedTime = 0.0
                
                // Debug information
                print("TTS Debug - Original text length: \(text.count), Processed text length: \(processedText.count)")
                print("TTS Debug - Word count: \(self.totalWords)")
                print("TTS Debug - First 100 chars: \(String(processedText.prefix(100)))")
                if processedText.count > 100 {
                    print("TTS Debug - Last 100 chars: \(String(processedText.suffix(100)))")
                }
                
                // Check for potential issues in processed text
                let hasEmptyLines = processedText.contains("\n\n\n")
                let hasMultipleSpaces = processedText.contains("   ")
                let hasSpecialChars = processedText.rangeOfCharacter(from: CharacterSet(charactersIn: "\u{00A0}\u{2000}-\u{200F}\u{2028}-\u{202F}\u{205F}-\u{206F}\u{3000}\u{FEFF}")) != nil
                
                print("TTS Debug - Has empty lines: \(hasEmptyLines), Multiple spaces: \(hasMultipleSpaces), Special chars: \(hasSpecialChars)")
                
                // Only reset chunking state for single text (not when called from chunked speech)
                if chunkCompletionHandler == nil {
                    self.isChunked = false
                    self.chunkedTexts = []
                    self.currentChunk = 0
                    self.totalChunks = 0
                }

                let utterance: AVSpeechUtterance
                
                if self.enableSSML {
                    // Create SSML utterance
                    let ssmlText = self.createSSMLFromText(processedText)
                    print("TTS Debug - Using SSML: \(String(ssmlText.prefix(200)))...")
                    
                    if self.validateSSML(ssmlText), let ssmlUtterance = AVSpeechUtterance(ssmlRepresentation: ssmlText) {
                        utterance = ssmlUtterance
                        // Note: When using SSML, rate, pitchMultiplier, and volume are controlled by SSML
                        // The voice property may be overridden by SSML voice tags
                    } else {
                        print("TTS Debug - SSML validation failed or unsupported, falling back to regular utterance")
                        utterance = AVSpeechUtterance(string: processedText)
                        utterance.voice = self.currentVoice
                        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, self.speechRate))
                        utterance.pitchMultiplier = 1.0
                        utterance.volume = 1.0
                    }
                } else {
                    // Create regular utterance
                    utterance = AVSpeechUtterance(string: processedText)
                    utterance.voice = self.currentVoice
                    utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, self.speechRate))
                    utterance.pitchMultiplier = 1.0
                    utterance.volume = 1.0
                }

                // Validate utterance before speaking
                guard !utterance.speechString.isEmpty else {
                    print("Error: Utterance speech string is empty")
                    return
                }
                
                // Additional validation for meaningful content
                let trimmedSpeech = utterance.speechString.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedSpeech.isEmpty else {
                    print("Error: Utterance speech string is empty after trimming")
                    return
                }
                
                // Check for potential issues that might cause TTS to stop
                let hasControlChars = utterance.speechString.rangeOfCharacter(from: CharacterSet.controlCharacters) != nil
                let hasInvalidChars = utterance.speechString.rangeOfCharacter(from: CharacterSet.illegalCharacters) != nil
                let hasZeroWidthChars = utterance.speechString.rangeOfCharacter(from: CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}")) != nil
                
                if hasControlChars {
                    print("Warning: Utterance contains control characters that might cause issues")
                    // Clean the utterance string if it has control characters
                    let cleanedString = utterance.speechString.replacingOccurrences(of: "[\u{00}-\u{08}\u{0B}\u{0C}\u{0E}-\u{1F}\u{7F}]", with: "", options: .regularExpression)
                    if cleanedString != utterance.speechString {
                        print("TTS Debug - Cleaning utterance string from \(utterance.speechString.count) to \(cleanedString.count) characters")
                        // Create a new utterance with cleaned string
                        let newUtterance = AVSpeechUtterance(string: cleanedString)
                        newUtterance.voice = utterance.voice
                        newUtterance.rate = utterance.rate
                        newUtterance.pitchMultiplier = utterance.pitchMultiplier
                        newUtterance.volume = utterance.volume
                        utterance = newUtterance
                    }
                }
                if hasInvalidChars {
                    print("Warning: Utterance contains invalid characters that might cause issues")
                }
                if hasZeroWidthChars {
                    print("Warning: Utterance contains zero-width characters that might cause issues")
                }
                
                // Check utterance string specifically
                print("TTS Debug - Utterance string length: \(utterance.speechString.count)")
                print("TTS Debug - Utterance first 50 chars: \(String(utterance.speechString.prefix(50)))")
                print("TTS Debug - Final utterance validation passed, proceeding to speak")

                self.currentUtterance = utterance

                self.utteranceStartDate = Date()
                self.synthesizer.speak(utterance)

                // Start progress tracking on a user-initiated queue
                self.startProgressTracking()
                
                // Start timeout timer to detect stuck TTS
                self.startTimeoutTimer()
            }
        }
    }
    
    func speakChunkedText(_ texts: [String], startChunk: Int = 0) {
        print("=== STARTING CHUNKED SPEECH ===")
        print("Starting chunked speech with \(texts.count) chunks, starting at chunk \(startChunk)")
        
        // Stop any current speech and tracking first on the main actor
        stopSpeaking()
        
        guard !texts.isEmpty else {
            print("Warning: No chunks provided for chunked speech")
            return
        }
        
        // Set up chunking state
        self.isChunked = true
        self.chunkedTexts = texts
        self.currentChunk = startChunk
        self.totalChunks = texts.count
        
        print("Chunking state set - isChunked: \(isChunked), totalChunks: \(totalChunks)")
        print("Chunked texts count: \(chunkedTexts.count)")
        
        // Start with the first chunk
        speakCurrentChunk()
    }
    
    private func speakCurrentChunk() {
        guard isChunked && currentChunk < chunkedTexts.count else {
            print("No more chunks to speak")
            return
        }
        
        let chunkText = chunkedTexts[currentChunk]
        let wordCount = chunkText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        print("Speaking chunk \(currentChunk + 1) of \(totalChunks) (\(wordCount) words)")
        
        // Use the regular speak method but with chunk completion handler
        print("Calling speak with chunk completion handler")
        speak(chunkText) { [weak self] in
            print("Chunk completion handler called")
            // Ensure we're still in chunked mode before handling completion
            guard let self = self, self.isChunked else {
                print("Chunk completion called but no longer in chunked mode")
                return
            }
            self.handleChunkCompletion()
        }
    }
    
    private func handleChunkCompletion() {
        guard isChunked else { 
            print("Chunk completion called but not in chunked mode")
            return 
        }
        
        print("Chunk \(currentChunk + 1) completed")
        currentChunk += 1
        
        if currentChunk < totalChunks {
            // Move to next chunk with a small delay to prevent race conditions
            print("Moving to chunk \(currentChunk + 1) of \(totalChunks)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.speakCurrentChunk()
            }
        } else {
            // All chunks completed
            print("All chunks completed - TTS finished")
            isChunked = false
            chunkedTexts = []
            currentChunk = 0
            totalChunks = 0
        }
    }
    
    private func startProgressTracking() {
        // Cancel any existing timer
        progressTimer?.cancel()
        progressTimer = nil

        // Create a timer on a user-initiated QoS queue to avoid priority inversion
        let queue = DispatchQueue(label: "tts.progress.timer", qos: .userInitiated)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1) // More frequent updates for better sync
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            // If not speaking, stop the timer
            if !self.isSpeaking {
                self.progressTimer?.cancel()
                self.progressTimer = nil
                return
            }

            // If paused, don't update progress
            if self.isPaused {
                return
            }

            guard self.currentUtterance != nil else { return }
            let rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, self.speechRate))

            // More accurate duration estimation based on words and rate
            let wordsPerMinute = max(100.0, Double(rate) * 200.0) // More realistic WPM range
            let wordsPerSecond = wordsPerMinute / 60.0
            let estimatedDuration = max(1.0, Double(self.totalWords) / wordsPerSecond)
            let start = self.utteranceStartDate ?? Date()
            let elapsed = Date().timeIntervalSince(start)
            
            // Account for paused time
            let actualElapsed = elapsed - self.totalPausedTime
            let progress = min(1.0, max(0.0, actualElapsed / estimatedDuration))

            // Publish updates on the main actor
            Task { @MainActor in
                self.readingProgress = progress
                self.currentWordIndex = Int(progress * Double(self.totalWords))
                
                // Update PDF extractor with current word (only if follow text is enabled)
                if self.settingsManager?.enableFollowText == true {
                    self.pdfExtractor?.updateCurrentWord(self.currentWordIndex)
                }
            }
        }
        progressTimer = timer
        timer.resume()
    }
    
    private func startTimeoutTimer() {
        // Cancel any existing timeout timer
        timeoutTimer?.cancel()
        timeoutTimer = nil
        
        // Create a timeout timer - if TTS doesn't finish in 30 seconds, assume it's stuck
        let queue = DispatchQueue(label: "tts.timeout.timer", qos: .userInitiated)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30.0) // 30 second timeout
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            // Check if we're still speaking and haven't made progress
            if self.isSpeaking && self.readingProgress < 0.1 {
                print("TTS Timeout detected - TTS appears to be stuck, forcing completion")
                
                Task { @MainActor in
                    // Force completion of current chunk
                    if let handler = self.chunkCompletionHandler {
                        self.chunkCompletionHandler = nil
                        handler()
                    }
                    
                    // Reset state
                    self.isSpeaking = false
                    self.isPaused = false
                    self.currentUtterance = nil
                    self.progressTimer?.cancel()
                    self.progressTimer = nil
                    self.timeoutTimer?.cancel()
                    self.timeoutTimer = nil
                    self.utteranceStartDate = nil
                }
            }
        }
        timeoutTimer = timer
        timer.resume()
    }
    
    func pauseSpeaking() {
        if isSpeaking && !isPaused {
            pausedTime = Date().timeIntervalSince(utteranceStartDate ?? Date())
            synthesizer.pauseSpeaking(at: .immediate)
        }
    }
    
    func resumeSpeaking() {
        if isPaused {
            // Add the paused time to total paused time
            totalPausedTime += pausedTime
            pausedTime = 0.0
            synthesizer.continueSpeaking()
        }
    }
    
    func stopSpeaking() {
        print("TTS Debug - Stopping speech, current utterance: \(currentUtterance != nil)")
        
        // Cancel all timers first
        progressTimer?.cancel()
        progressTimer = nil
        timeoutTimer?.cancel()
        timeoutTimer = nil
        
        // Stop the synthesizer
        synthesizer.stopSpeaking(at: .immediate)
        
        // Clear utterance reference and reset state
        currentUtterance = nil
        utteranceStartDate = nil
        readingProgress = 0.0
        currentWordIndex = 0
        isSpeaking = false
        isPaused = false
        
        print("TTS Debug - Speech stopped, state reset")
    }
    
    func setSpeechRate(_ rate: Float) {
        speechRate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
        settingsManager?.setSpeechRate(speechRate)
        
        // Note: Changing rate mid-utterance is not applied by AVSpeechSynthesizer; changes will take effect on next speak.
    }
    
    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        currentVoice = voice
        settingsManager?.setVoice(voice)
    }
    
    func previewVoice(_ voice: AVSpeechSynthesisVoice) {
        stopSpeaking()
        
        let previewText = "Hello, this is a preview of the \(voice.name) voice. How does it sound?"
        let utterance = AVSpeechUtterance(string: previewText)
        utterance.voice = voice
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, speechRate))
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }
    
    func previewSpeed(_ rate: Float) {
        stopSpeaking()
        
        let previewText = "This is a preview of the reading speed. How does this pace sound to you?"
        let utterance = AVSpeechUtterance(string: previewText)
        utterance.voice = currentVoice
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }
    
    nonisolated var availableVoices: [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
    }
    
    // MARK: - Personal Voice Authorization
    
    func checkPersonalVoiceAuthorization() {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            isPersonalVoiceAuthorized = true
            personalVoiceStatus = "Authorized"
        case .denied:
            isPersonalVoiceAuthorized = false
            personalVoiceStatus = "Denied"
        case .restricted:
            isPersonalVoiceAuthorized = false
            personalVoiceStatus = "Restricted"
        case .notDetermined:
            isPersonalVoiceAuthorized = false
            personalVoiceStatus = "Not requested"
        @unknown default:
            isPersonalVoiceAuthorized = false
            personalVoiceStatus = "Unknown"
        }
    }
    
    func requestPersonalVoiceAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.checkPersonalVoiceAuthorization()
            }
        }
    }
    
    // MARK: - SSML Support
    
    func setSSMLEnabled(_ enabled: Bool) {
        enableSSML = enabled
        settingsManager?.setSSMLEnabled(enabled)
    }
    
    func createCustomSSML(text: String, voice: String? = nil, rate: Double? = nil, pitch: Double? = nil, volume: Double? = nil) -> String {
        let voiceName = voice ?? currentVoice?.name ?? "default"
        let language = currentVoice?.language ?? "en-US"
        let ssmlRate = rate ?? Double(speechRate) * 2.0
        let ssmlPitch = pitch ?? 1.0
        let ssmlVolume = volume ?? 1.0
        
        let ssmlText = """
        <speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="\(language)">
            <voice name="\(voiceName)">
                <prosody rate="\(String(format: "%.1f", ssmlRate))" pitch="\(String(format: "%.1f", ssmlPitch))" volume="\(String(format: "%.1f", ssmlVolume))">
                    \(escapeSSMLText(text))
                </prosody>
            </voice>
        </speak>
        """
        
        return ssmlText
    }
    
    private func createSSMLFromText(_ text: String) -> String {
        // Enhanced SSML wrapper with voice and prosody settings
        let voiceName = currentVoice?.name ?? "default"
        let language = currentVoice?.language ?? "en-US"
        
        // Convert speech rate to SSML rate format (0.1-10.0, where 1.0 is normal)
        let ssmlRate = max(0.1, min(10.0, Double(speechRate) * 2.0))
        
        let ssmlText = """
        <speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="\(language)">
            <voice name="\(voiceName)">
                <prosody rate="\(String(format: "%.1f", ssmlRate))" pitch="1.0" volume="1.0">
                    \(escapeSSMLText(text))
                </prosody>
            </voice>
        </speak>
        """
        return ssmlText
    }
    
    private func escapeSSMLText(_ text: String) -> String {
        var escapedText = text
        
        // Escape XML special characters
        escapedText = escapedText.replacingOccurrences(of: "&", with: "&amp;")
        escapedText = escapedText.replacingOccurrences(of: "<", with: "&lt;")
        escapedText = escapedText.replacingOccurrences(of: ">", with: "&gt;")
        escapedText = escapedText.replacingOccurrences(of: "\"", with: "&quot;")
        escapedText = escapedText.replacingOccurrences(of: "'", with: "&apos;")
        
        return escapedText
    }
    
    private func validateSSML(_ ssml: String) -> Bool {
        // Basic SSML validation
        let requiredElements = ["<speak", "</speak>"]
        for element in requiredElements {
            if !ssml.contains(element) {
                print("SSML Validation Error: Missing required element '\(element)'")
                return false
            }
        }
        
        // Check for proper XML structure
        let openSpeak = ssml.components(separatedBy: "<speak").count - 1
        let closeSpeak = ssml.components(separatedBy: "</speak>").count - 1
        
        if openSpeak != closeSpeak {
            print("SSML Validation Error: Mismatched speak tags")
            return false
        }
        
        return true
    }
    
    private func preprocessTextForTTS(_ text: String) -> String {
        var processedText = text
        
        // Handle LaTeX math delimiters more carefully to preserve content
        processedText = processedText.replacingOccurrences(of: "\\(", with: " (")
        processedText = processedText.replacingOccurrences(of: "\\)", with: ") ")
        processedText = processedText.replacingOccurrences(of: "\\[", with: " [")
        processedText = processedText.replacingOccurrences(of: "\\]", with: "] ")
        processedText = processedText.replacingOccurrences(of: "$$", with: " ")
        processedText = processedText.replacingOccurrences(of: "$", with: " ")
        
        // Handle common LaTeX commands
        processedText = processedText.replacingOccurrences(of: "\\frac{", with: " fraction ")
        processedText = processedText.replacingOccurrences(of: "\\sqrt{", with: " square root of ")
        processedText = processedText.replacingOccurrences(of: "\\sum", with: " sum ")
        processedText = processedText.replacingOccurrences(of: "\\int", with: " integral ")
        processedText = processedText.replacingOccurrences(of: "\\lim", with: " limit ")
        processedText = processedText.replacingOccurrences(of: "\\infty", with: " infinity ")
        processedText = processedText.replacingOccurrences(of: "\\alpha", with: " alpha ")
        processedText = processedText.replacingOccurrences(of: "\\beta", with: " beta ")
        processedText = processedText.replacingOccurrences(of: "\\gamma", with: " gamma ")
        processedText = processedText.replacingOccurrences(of: "\\delta", with: " delta ")
        processedText = processedText.replacingOccurrences(of: "\\epsilon", with: " epsilon ")
        processedText = processedText.replacingOccurrences(of: "\\theta", with: " theta ")
        processedText = processedText.replacingOccurrences(of: "\\lambda", with: " lambda ")
        processedText = processedText.replacingOccurrences(of: "\\mu", with: " mu ")
        processedText = processedText.replacingOccurrences(of: "\\pi", with: " pi ")
        processedText = processedText.replacingOccurrences(of: "\\sigma", with: " sigma ")
        processedText = processedText.replacingOccurrences(of: "\\tau", with: " tau ")
        processedText = processedText.replacingOccurrences(of: "\\phi", with: " phi ")
        processedText = processedText.replacingOccurrences(of: "\\omega", with: " omega ")
        
        // Handle mathematical operators
        processedText = processedText.replacingOccurrences(of: "\\times", with: " times ")
        processedText = processedText.replacingOccurrences(of: "\\div", with: " divided by ")
        processedText = processedText.replacingOccurrences(of: "\\pm", with: " plus or minus ")
        processedText = processedText.replacingOccurrences(of: "\\mp", with: " minus or plus ")
        processedText = processedText.replacingOccurrences(of: "\\leq", with: " less than or equal to ")
        processedText = processedText.replacingOccurrences(of: "\\geq", with: " greater than or equal to ")
        processedText = processedText.replacingOccurrences(of: "\\neq", with: " not equal to ")
        processedText = processedText.replacingOccurrences(of: "\\approx", with: " approximately equal to ")
        processedText = processedText.replacingOccurrences(of: "\\equiv", with: " equivalent to ")
        processedText = processedText.replacingOccurrences(of: "\\propto", with: " proportional to ")
        processedText = processedText.replacingOccurrences(of: "\\in", with: " in ")
        processedText = processedText.replacingOccurrences(of: "\\notin", with: " not in ")
        processedText = processedText.replacingOccurrences(of: "\\subset", with: " subset of ")
        processedText = processedText.replacingOccurrences(of: "\\supset", with: " superset of ")
        processedText = processedText.replacingOccurrences(of: "\\cup", with: " union ")
        processedText = processedText.replacingOccurrences(of: "\\cap", with: " intersection ")
        processedText = processedText.replacingOccurrences(of: "\\emptyset", with: " empty set ")
        processedText = processedText.replacingOccurrences(of: "\\forall", with: " for all ")
        processedText = processedText.replacingOccurrences(of: "\\exists", with: " there exists ")
        processedText = processedText.replacingOccurrences(of: "\\rightarrow", with: " implies ")
        processedText = processedText.replacingOccurrences(of: "\\leftarrow", with: " implied by ")
        processedText = processedText.replacingOccurrences(of: "\\leftrightarrow", with: " if and only if ")
        
        // Handle superscripts and subscripts
        processedText = processedText.replacingOccurrences(of: "^{", with: " to the power of ")
        processedText = processedText.replacingOccurrences(of: "_{", with: " sub ")
        processedText = processedText.replacingOccurrences(of: "}", with: " ")
        
        // Handle common mathematical symbols
        processedText = processedText.replacingOccurrences(of: "∑", with: " sum ")
        processedText = processedText.replacingOccurrences(of: "∏", with: " product ")
        processedText = processedText.replacingOccurrences(of: "∫", with: " integral ")
        processedText = processedText.replacingOccurrences(of: "√", with: " square root ")
        processedText = processedText.replacingOccurrences(of: "∞", with: " infinity ")
        processedText = processedText.replacingOccurrences(of: "α", with: " alpha ")
        processedText = processedText.replacingOccurrences(of: "β", with: " beta ")
        processedText = processedText.replacingOccurrences(of: "γ", with: " gamma ")
        processedText = processedText.replacingOccurrences(of: "δ", with: " delta ")
        processedText = processedText.replacingOccurrences(of: "ε", with: " epsilon ")
        processedText = processedText.replacingOccurrences(of: "θ", with: " theta ")
        processedText = processedText.replacingOccurrences(of: "λ", with: " lambda ")
        processedText = processedText.replacingOccurrences(of: "μ", with: " mu ")
        processedText = processedText.replacingOccurrences(of: "π", with: " pi ")
        processedText = processedText.replacingOccurrences(of: "σ", with: " sigma ")
        processedText = processedText.replacingOccurrences(of: "τ", with: " tau ")
        processedText = processedText.replacingOccurrences(of: "φ", with: " phi ")
        processedText = processedText.replacingOccurrences(of: "ω", with: " omega ")
        processedText = processedText.replacingOccurrences(of: "×", with: " times ")
        processedText = processedText.replacingOccurrences(of: "÷", with: " divided by ")
        processedText = processedText.replacingOccurrences(of: "±", with: " plus or minus ")
        processedText = processedText.replacingOccurrences(of: "≤", with: " less than or equal to ")
        processedText = processedText.replacingOccurrences(of: "≥", with: " greater than or equal to ")
        processedText = processedText.replacingOccurrences(of: "≠", with: " not equal to ")
        processedText = processedText.replacingOccurrences(of: "≈", with: " approximately equal to ")
        processedText = processedText.replacingOccurrences(of: "≡", with: " equivalent to ")
        processedText = processedText.replacingOccurrences(of: "∝", with: " proportional to ")
        processedText = processedText.replacingOccurrences(of: "∈", with: " in ")
        processedText = processedText.replacingOccurrences(of: "∉", with: " not in ")
        processedText = processedText.replacingOccurrences(of: "⊂", with: " subset of ")
        processedText = processedText.replacingOccurrences(of: "⊃", with: " superset of ")
        processedText = processedText.replacingOccurrences(of: "∪", with: " union ")
        processedText = processedText.replacingOccurrences(of: "∩", with: " intersection ")
        processedText = processedText.replacingOccurrences(of: "∅", with: " empty set ")
        processedText = processedText.replacingOccurrences(of: "∀", with: " for all ")
        processedText = processedText.replacingOccurrences(of: "∃", with: " there exists ")
        processedText = processedText.replacingOccurrences(of: "→", with: " implies ")
        processedText = processedText.replacingOccurrences(of: "←", with: " implied by ")
        processedText = processedText.replacingOccurrences(of: "↔", with: " if and only if ")
        
        // Clean up excessive whitespace but preserve word boundaries
        processedText = processedText.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        
        // Remove any remaining problematic characters that might cause TTS to stop
        processedText = processedText.replacingOccurrences(of: "\u{00A0}", with: " ") // Non-breaking space
        processedText = processedText.replacingOccurrences(of: "\u{2000}-\u{200F}", with: " ", options: .regularExpression) // Various spaces
        processedText = processedText.replacingOccurrences(of: "\u{2028}-\u{202F}", with: " ", options: .regularExpression) // Line/paragraph separators
        processedText = processedText.replacingOccurrences(of: "\u{205F}-\u{206F}", with: " ", options: .regularExpression) // More spaces
        processedText = processedText.replacingOccurrences(of: "\u{3000}", with: " ") // Ideographic space
        processedText = processedText.replacingOccurrences(of: "\u{FEFF}", with: "") // Zero-width no-break space
        
        // Remove all control characters except newlines and tabs
        processedText = processedText.replacingOccurrences(of: "[\u{00}-\u{08}\u{0B}\u{0C}\u{0E}-\u{1F}\u{7F}]", with: "", options: .regularExpression)
        
        // Remove any remaining problematic Unicode characters
        processedText = processedText.replacingOccurrences(of: "[\u{200B}-\u{200D}\u{2060}\u{FEFF}]", with: "", options: .regularExpression) // Zero-width characters
        
        // Clean up any remaining problematic characters that might cause audio issues
        processedText = processedText.replacingOccurrences(of: "[\u{202A}-\u{202E}\u{2066}-\u{2069}]", with: "", options: .regularExpression) // Directional formatting characters
        
        // Final cleanup
        processedText = processedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure we have valid content
        if processedText.isEmpty {
            processedText = "No content available for speech synthesis."
        }
        
        return processedText
    }
}

@MainActor extension TextToSpeechManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("Speech synthesizer did start utterance")
        print("Utterance speech string length: \(utterance.speechString.count)")
        print("Utterance speech string preview: \(String(utterance.speechString.prefix(100)))")
        
        self.isSpeaking = true
        self.isPaused = false
        self.utteranceStartDate = Date()
        self.startProgressTracking()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        self.isPaused = true
        // Record the time when paused
        if let startDate = self.utteranceStartDate {
            self.pausedTime = Date().timeIntervalSince(startDate)
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        self.isPaused = false
        // Add the paused time to total paused time
        self.totalPausedTime += self.pausedTime
        self.pausedTime = 0.0
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("Speech synthesizer did finish utterance")
        print("Current chunk completion handler: \(self.chunkCompletionHandler != nil)")
        print("Is chunked: \(self.isChunked)")
        print("Current chunk: \(self.currentChunk) of \(self.totalChunks)")
        print("Utterance speech string length: \(utterance.speechString.count)")
        print("Utterance speech string preview: \(String(utterance.speechString.prefix(100)))")
        print("Reading progress when finished: \(self.readingProgress)")
        print("Total words: \(self.totalWords), Current word index: \(self.currentWordIndex)")
        print("Current utterance reference: \(self.currentUtterance != nil)")
        print("Utterance identity match: \(self.currentUtterance === utterance)")
        
        // Check if this is the current utterance or if we should process it anyway
        let isCurrentUtterance = self.currentUtterance === utterance
        let hasCompletionHandler = self.chunkCompletionHandler != nil
        
        print("Processing didFinish - isCurrent: \(isCurrentUtterance), hasHandler: \(hasCompletionHandler)")
        
        // Process completion if this is the current utterance OR if we have a completion handler
        // (in case of race conditions where utterance reference was cleared)
        guard isCurrentUtterance || hasCompletionHandler else {
            print("Ignoring didFinish - not current utterance and no completion handler")
            return
        }
        
        self.isSpeaking = false
        self.isPaused = false
        self.currentUtterance = nil
        self.progressTimer?.cancel()
        self.progressTimer = nil
        self.timeoutTimer?.cancel()
        self.timeoutTimer = nil
        self.utteranceStartDate = nil
        
        // Call chunk completion handler if available
        if let handler = self.chunkCompletionHandler {
            print("Calling chunk completion handler")
            self.chunkCompletionHandler = nil
            handler()
        } else {
            print("No chunk completion handler to call")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("Speech synthesizer did cancel utterance")
        print("Current chunk completion handler: \(self.chunkCompletionHandler != nil)")
        print("Is chunked: \(self.isChunked)")
        print("Current chunk: \(self.currentChunk) of \(self.totalChunks)")
        
        self.isSpeaking = false
        self.isPaused = false
        self.currentUtterance = nil
        self.progressTimer?.cancel()
        self.progressTimer = nil
        self.utteranceStartDate = nil
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        print("Speech synthesizer will speak range: \(characterRange.location)-\(characterRange.location + characterRange.length)")
        let textToSpeak = (utterance.speechString as NSString).substring(with: characterRange)
        print("Text to speak: \(String(textToSpeak.prefix(50)))...")
    }
}

