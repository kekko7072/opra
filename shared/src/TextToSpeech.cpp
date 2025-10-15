#include "TextToSpeech.h"
#include <algorithm>
#include <thread>
#include <chrono>

#ifdef _WIN32
    #include "TextToSpeech_Windows.cpp"
#elif __APPLE__
    #include "TextToSpeech_macOS.cpp"
#endif

namespace Opra {

class TextToSpeech::Impl {
public:
    Impl() = default;
    ~Impl() = default;
    
    bool speak(const std::string& text) {
        if (text.empty()) return false;
        
        // Clean the text
        std::string cleanedText = cleanTextForTTS(text);
        if (cleanedText.empty()) return false;
        
        // Platform-specific implementation
#ifdef _WIN32
        return speakWindows(cleanedText);
#elif __APPLE__
        return speakMacOS(cleanedText);
#else
        return false; // Unsupported platform
#endif
    }
    
    bool speakChunked(const std::vector<std::string>& chunks, int startChunk) {
        if (chunks.empty() || startChunk >= chunks.size()) return false;
        
        // Store chunks for sequential playback
        this->chunks = chunks;
        this->currentChunk = startChunk;
        this->isChunked = true;
        
        // Start with the first chunk
        return speakCurrentChunk();
    }
    
    void pause() {
        if (state == SpeechState::Speaking) {
#ifdef _WIN32
            pauseWindows();
#elif __APPLE__
            pauseMacOS();
#endif
            state = SpeechState::Paused;
            if (speechPausedCallback) {
                speechPausedCallback();
            }
        }
    }
    
    void resume() {
        if (state == SpeechState::Paused) {
#ifdef _WIN32
            resumeWindows();
#elif __APPLE__
            resumeMacOS();
#endif
            state = SpeechState::Speaking;
            if (speechResumedCallback) {
                speechResumedCallback();
            }
        }
    }
    
    void stop() {
        if (state != SpeechState::Stopped) {
#ifdef _WIN32
            stopWindows();
#elif __APPLE__
            stopMacOS();
#endif
            state = SpeechState::Stopped;
            isChunked = false;
            chunks.clear();
            currentChunk = 0;
        }
    }
    
    SpeechState getState() const {
        return state;
    }
    
    bool isSpeaking() const {
        return state == SpeechState::Speaking;
    }
    
    bool isPaused() const {
        return state == SpeechState::Paused;
    }
    
    void setSettings(const SpeechSettings& settings) {
        this->settings = settings;
        
        // Apply settings to platform-specific implementation
#ifdef _WIN32
        setSettingsWindows(settings);
#elif __APPLE__
        setSettingsMacOS(settings);
#endif
    }
    
    SpeechSettings getSettings() const {
        return settings;
    }
    
    std::vector<Voice> getAvailableVoices() const {
#ifdef _WIN32
        return getAvailableVoicesWindows();
#elif __APPLE__
        return getAvailableVoicesMacOS();
#else
        return {};
#endif
    }
    
    bool setVoice(const std::string& voiceId) {
        settings.voiceId = voiceId;
        
#ifdef _WIN32
        return setVoiceWindows(voiceId);
#elif __APPLE__
        return setVoiceMacOS(voiceId);
#else
        return false;
#endif
    }
    
    Voice getCurrentVoice() const {
#ifdef _WIN32
        return getCurrentVoiceWindows();
#elif __APPLE__
        return getCurrentVoiceMacOS();
#else
        return {};
#endif
    }
    
    float getProgress() const {
        return progress;
    }
    
    int getCurrentWordIndex() const {
        return currentWordIndex;
    }
    
    int getTotalWords() const {
        return totalWords;
    }
    
    void setSpeechStartedCallback(SpeechStartedCallback callback) {
        speechStartedCallback = callback;
    }
    
    void setSpeechFinishedCallback(SpeechFinishedCallback callback) {
        speechFinishedCallback = callback;
    }
    
    void setSpeechPausedCallback(SpeechPausedCallback callback) {
        speechPausedCallback = callback;
    }
    
    void setSpeechResumedCallback(SpeechResumedCallback callback) {
        speechResumedCallback = callback;
    }
    
    void setProgressCallback(ProgressCallback callback) {
        progressCallback = callback;
    }
    
    bool initialize() {
#ifdef _WIN32
        return initializeWindows();
#elif __APPLE__
        return initializeMacOS();
#else
        return false;
#endif
    }
    
    void cleanup() {
#ifdef _WIN32
        cleanupWindows();
#elif __APPLE__
        cleanupMacOS();
#endif
    }
    
    // Callbacks for platform-specific implementations
    void onSpeechStarted() {
        state = SpeechState::Speaking;
        if (speechStartedCallback) {
            speechStartedCallback();
        }
    }
    
    void onSpeechFinished() {
        if (isChunked && currentChunk < chunks.size() - 1) {
            // Move to next chunk
            currentChunk++;
            speakCurrentChunk();
        } else {
            // All chunks finished or single text finished
            state = SpeechState::Stopped;
            isChunked = false;
            chunks.clear();
            currentChunk = 0;
            
            if (speechFinishedCallback) {
                speechFinishedCallback();
            }
        }
    }
    
    void onProgress(float progress, int currentWord, int totalWords) {
        this->progress = progress;
        this->currentWordIndex = currentWord;
        this->totalWords = totalWords;
        
        if (progressCallback) {
            progressCallback(progress, currentWord, totalWords);
        }
    }
    
private:
    SpeechState state = SpeechState::Stopped;
    SpeechSettings settings;
    std::vector<std::string> chunks;
    int currentChunk = 0;
    bool isChunked = false;
    float progress = 0.0f;
    int currentWordIndex = 0;
    int totalWords = 0;
    
    // Callbacks
    SpeechStartedCallback speechStartedCallback;
    SpeechFinishedCallback speechFinishedCallback;
    SpeechPausedCallback speechPausedCallback;
    SpeechResumedCallback speechResumedCallback;
    ProgressCallback progressCallback;
    
    bool speakCurrentChunk() {
        if (isChunked && currentChunk < chunks.size()) {
            return speak(chunks[currentChunk]);
        }
        return false;
    }
    
    std::string cleanTextForTTS(const std::string& text) {
        // Basic text cleaning - more sophisticated cleaning can be added
        std::string cleaned = text;
        
        // Remove control characters except newlines and tabs
        cleaned = std::regex_replace(cleaned, std::regex(R"([\x00-\x08\x0B\x0C\x0E-\x1F\x7F])"), "");
        
        // Clean up multiple spaces
        cleaned = std::regex_replace(cleaned, std::regex(R"(\s{2,})"), " ");
        
        // Trim whitespace
        cleaned = trim(cleaned);
        
        return cleaned;
    }
    
    std::string trim(const std::string& str) {
        size_t first = str.find_first_not_of(' ');
        if (first == std::string::npos) return "";
        size_t last = str.find_last_not_of(' ');
        return str.substr(first, (last - first + 1));
    }
    
    // Platform-specific method declarations
#ifdef _WIN32
    bool speakWindows(const std::string& text);
    void pauseWindows();
    void resumeWindows();
    void stopWindows();
    void setSettingsWindows(const SpeechSettings& settings);
    std::vector<Voice> getAvailableVoicesWindows() const;
    bool setVoiceWindows(const std::string& voiceId);
    Voice getCurrentVoiceWindows() const;
    bool initializeWindows();
    void cleanupWindows();
#elif __APPLE__
    bool speakMacOS(const std::string& text);
    void pauseMacOS();
    void resumeMacOS();
    void stopMacOS();
    void setSettingsMacOS(const SpeechSettings& settings);
    std::vector<Voice> getAvailableVoicesMacOS() const;
    bool setVoiceMacOS(const std::string& voiceId);
    Voice getCurrentVoiceMacOS() const;
    bool initializeMacOS();
    void cleanupMacOS();
#endif
};

// Constructor and destructor
TextToSpeech::TextToSpeech() : pImpl(std::make_unique<Impl>()) {}
TextToSpeech::~TextToSpeech() = default;

// Public method implementations
bool TextToSpeech::speak(const std::string& text) {
    return pImpl->speak(text);
}

bool TextToSpeech::speakChunked(const std::vector<std::string>& chunks, int startChunk) {
    return pImpl->speakChunked(chunks, startChunk);
}

void TextToSpeech::pause() {
    pImpl->pause();
}

void TextToSpeech::resume() {
    pImpl->resume();
}

void TextToSpeech::stop() {
    pImpl->stop();
}

TextToSpeech::SpeechState TextToSpeech::getState() const {
    return pImpl->getState();
}

bool TextToSpeech::isSpeaking() const {
    return pImpl->isSpeaking();
}

bool TextToSpeech::isPaused() const {
    return pImpl->isPaused();
}

void TextToSpeech::setSettings(const SpeechSettings& settings) {
    pImpl->setSettings(settings);
}

TextToSpeech::SpeechSettings TextToSpeech::getSettings() const {
    return pImpl->getSettings();
}

std::vector<TextToSpeech::Voice> TextToSpeech::getAvailableVoices() const {
    return pImpl->getAvailableVoices();
}

bool TextToSpeech::setVoice(const std::string& voiceId) {
    return pImpl->setVoice(voiceId);
}

TextToSpeech::Voice TextToSpeech::getCurrentVoice() const {
    return pImpl->getCurrentVoice();
}

float TextToSpeech::getProgress() const {
    return pImpl->getProgress();
}

int TextToSpeech::getCurrentWordIndex() const {
    return pImpl->getCurrentWordIndex();
}

int TextToSpeech::getTotalWords() const {
    return pImpl->getTotalWords();
}

void TextToSpeech::setSpeechStartedCallback(SpeechStartedCallback callback) {
    pImpl->setSpeechStartedCallback(callback);
}

void TextToSpeech::setSpeechFinishedCallback(SpeechFinishedCallback callback) {
    pImpl->setSpeechFinishedCallback(callback);
}

void TextToSpeech::setSpeechPausedCallback(SpeechPausedCallback callback) {
    pImpl->setSpeechPausedCallback(callback);
}

void TextToSpeech::setSpeechResumedCallback(SpeechResumedCallback callback) {
    pImpl->setSpeechResumedCallback(callback);
}

void TextToSpeech::setProgressCallback(ProgressCallback callback) {
    pImpl->setProgressCallback(callback);
}

bool TextToSpeech::initialize() {
    return pImpl->initialize();
}

void TextToSpeech::cleanup() {
    pImpl->cleanup();
}

} // namespace Opra