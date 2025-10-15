#pragma once

#include <string>
#include <vector>
#include <functional>
#include <memory>

namespace Opra {
    class TextToSpeech {
    public:
        struct Voice {
            std::string id;
            std::string name;
            std::string language;
            bool isDefault;
        };
        
        struct SpeechSettings {
            float rate = 0.5f;
            float pitch = 1.0f;
            float volume = 1.0f;
            std::string voiceId;
        };
        
        enum class SpeechState {
            Stopped,
            Speaking,
            Paused
        };
        
        // Callback types
        using SpeechStartedCallback = std::function<void()>;
        using SpeechFinishedCallback = std::function<void()>;
        using SpeechPausedCallback = std::function<void()>;
        using SpeechResumedCallback = std::function<void()>;
        using ProgressCallback = std::function<void(float progress, int currentWord, int totalWords)>;
        
        TextToSpeech();
        ~TextToSpeech();
        
        // Speech control
        bool speak(const std::string& text);
        bool speakChunked(const std::vector<std::string>& chunks, int startChunk = 0);
        void pause();
        void resume();
        void stop();
        
        // State queries
        SpeechState getState() const;
        bool isSpeaking() const;
        bool isPaused() const;
        
        // Settings
        void setSettings(const SpeechSettings& settings);
        SpeechSettings getSettings() const;
        
        // Voice management
        std::vector<Voice> getAvailableVoices() const;
        bool setVoice(const std::string& voiceId);
        Voice getCurrentVoice() const;
        
        // Progress tracking
        float getProgress() const;
        int getCurrentWordIndex() const;
        int getTotalWords() const;
        
        // Callbacks
        void setSpeechStartedCallback(SpeechStartedCallback callback);
        void setSpeechFinishedCallback(SpeechFinishedCallback callback);
        void setSpeechPausedCallback(SpeechPausedCallback callback);
        void setSpeechResumedCallback(SpeechResumedCallback callback);
        void setProgressCallback(ProgressCallback callback);
        
        // Platform-specific initialization
        bool initialize();
        void cleanup();
        
    private:
        class Impl;
        std::unique_ptr<Impl> pImpl;
    };
}