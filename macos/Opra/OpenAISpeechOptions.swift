/// Voice and instruction support differs between the Speech API models.
enum OpenAISpeechOptions {
    static let voices = [
        "alloy", "ash", "ballad", "coral", "echo", "fable", "nova",
        "onyx", "sage", "shimmer", "verse", "marin", "cedar"
    ]
    static let legacyVoices = ["alloy", "ash", "coral", "echo", "fable", "onyx", "nova", "sage", "shimmer"]

    static func supportsInstructions(_ model: String) -> Bool {
        model.hasPrefix("gpt-4o-mini-tts")
    }

    static func voices(for model: String) -> [String] {
        supportsInstructions(model) ? voices : legacyVoices
    }

    static func validVoice(_ voice: String, model: String) -> String {
        let supported = voices(for: model)
        return supported.contains(voice) ? voice : (supportsInstructions(model) ? "marin" : "alloy")
    }
}
