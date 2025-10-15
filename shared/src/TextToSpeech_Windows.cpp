#ifdef _WIN32

#include "TextToSpeech.h"
#include <windows.h>
#include <sapi.h>
#include <sphelper.h>
#include <string>
#include <vector>
#include <thread>
#include <chrono>

#pragma comment(lib, "sapi.lib")

namespace Opra {

class TextToSpeech::Impl {
public:
    Impl() : pSAPI(nullptr), pVoice(nullptr), pStream(nullptr), isInitialized(false) {}
    
    ~Impl() {
        cleanup();
    }
    
    bool speakWindows(const std::string& text) {
        if (!isInitialized) {
            if (!initialize()) return false;
        }
        
        // Convert string to wide string
        int wideLen = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
        std::vector<wchar_t> wideText(wideLen);
        MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, wideText.data(), wideLen);
        
        // Speak the text
        HRESULT hr = pSAPI->Speak(wideText.data(), SPF_ASYNC | SPF_IS_NOT_XML, nullptr);
        if (SUCCEEDED(hr)) {
            onSpeechStarted();
            return true;
        }
        
        return false;
    }
    
    void pauseWindows() {
        if (pSAPI) {
            pSAPI->Pause();
        }
    }
    
    void resumeWindows() {
        if (pSAPI) {
            pSAPI->Resume();
        }
    }
    
    void stopWindows() {
        if (pSAPI) {
            pSAPI->Speak(nullptr, SPF_PURGEBEFORESPEAK, nullptr);
        }
    }
    
    void setSettingsWindows(const SpeechSettings& settings) {
        this->settings = settings;
        
        if (pVoice) {
            // Set rate (convert from 0.0-1.0 to SAPI range -10 to 10)
            int sapiRate = (int)((settings.rate - 0.5f) * 20.0f);
            sapiRate = max(-10, min(10, sapiRate));
            pVoice->SetRate(sapiRate);
            
            // Set volume (convert from 0.0-1.0 to SAPI range 0-100)
            int sapiVolume = (int)(settings.volume * 100.0f);
            sapiVolume = max(0, min(100, sapiVolume));
            pVoice->SetVolume(sapiVolume);
        }
    }
    
    std::vector<Voice> getAvailableVoicesWindows() const {
        std::vector<Voice> voices;
        
        if (!isInitialized) {
            return voices;
        }
        
        // Get available voices
        CComPtr<IEnumSpObjectTokens> pEnum;
        HRESULT hr = SpEnumTokens(SPCAT_VOICES, nullptr, nullptr, &pEnum);
        if (SUCCEEDED(hr)) {
            CComPtr<ISpObjectToken> pToken;
            while (pEnum->Next(1, &pToken, nullptr) == S_OK) {
                Voice voice;
                
                // Get voice name
                CComPtr<ISpDataKey> pDataKey;
                if (SUCCEEDED(pToken->OpenKey(L"Attributes", &pDataKey))) {
                    WCHAR* name = nullptr;
                    if (SUCCEEDED(pDataKey->GetStringValue(L"Name", &name))) {
                        // Convert wide string to UTF-8
                        int utf8Len = WideCharToMultiByte(CP_UTF8, 0, name, -1, nullptr, 0, nullptr, nullptr);
                        std::vector<char> utf8Name(utf8Len);
                        WideCharToMultiByte(CP_UTF8, 0, name, -1, utf8Name.data(), utf8Len, nullptr, nullptr);
                        voice.name = utf8Name.data();
                        
                        CoTaskMemFree(name);
                    }
                    
                    // Get language
                    WCHAR* language = nullptr;
                    if (SUCCEEDED(pDataKey->GetStringValue(L"Language", &language))) {
                        int utf8Len = WideCharToMultiByte(CP_UTF8, 0, language, -1, nullptr, 0, nullptr, nullptr);
                        std::vector<char> utf8Lang(utf8Len);
                        WideCharToMultiByte(CP_UTF8, 0, language, -1, utf8Lang.data(), utf8Len, nullptr, nullptr);
                        voice.language = utf8Lang.data();
                        
                        CoTaskMemFree(language);
                    }
                }
                
                // Get voice ID
                WCHAR* id = nullptr;
                if (SUCCEEDED(pToken->GetId(&id))) {
                    int utf8Len = WideCharToMultiByte(CP_UTF8, 0, id, -1, nullptr, 0, nullptr, nullptr);
                    std::vector<char> utf8Id(utf8Len);
                    WideCharToMultiByte(CP_UTF8, 0, id, -1, utf8Id.data(), utf8Len, nullptr, nullptr);
                    voice.id = utf8Id.data();
                    
                    CoTaskMemFree(id);
                }
                
                voices.push_back(voice);
                pToken.Release();
            }
        }
        
        return voices;
    }
    
    bool setVoiceWindows(const std::string& voiceId) {
        if (!isInitialized) {
            return false;
        }
        
        // Convert string to wide string
        int wideLen = MultiByteToWideChar(CP_UTF8, 0, voiceId.c_str(), -1, nullptr, 0);
        std::vector<wchar_t> wideId(wideLen);
        MultiByteToWideChar(CP_UTF8, 0, voiceId.c_str(), -1, wideId.data(), wideLen);
        
        // Find the voice token
        CComPtr<ISpObjectToken> pToken;
        HRESULT hr = SpGetTokenFromId(wideId.data(), &pToken);
        if (SUCCEEDED(hr)) {
            // Set the voice
            hr = pSAPI->SetVoice(pToken);
            if (SUCCEEDED(hr)) {
                pVoice = pToken;
                return true;
            }
        }
        
        return false;
    }
    
    Voice getCurrentVoiceWindows() const {
        Voice voice;
        
        if (pVoice) {
            // Get voice name
            CComPtr<ISpDataKey> pDataKey;
            if (SUCCEEDED(pVoice->OpenKey(L"Attributes", &pDataKey))) {
                WCHAR* name = nullptr;
                if (SUCCEEDED(pDataKey->GetStringValue(L"Name", &name))) {
                    int utf8Len = WideCharToMultiByte(CP_UTF8, 0, name, -1, nullptr, 0, nullptr, nullptr);
                    std::vector<char> utf8Name(utf8Len);
                    WideCharToMultiByte(CP_UTF8, 0, name, -1, utf8Name.data(), utf8Len, nullptr, nullptr);
                    voice.name = utf8Name.data();
                    
                    CoTaskMemFree(name);
                }
                
                WCHAR* language = nullptr;
                if (SUCCEEDED(pDataKey->GetStringValue(L"Language", &language))) {
                    int utf8Len = WideCharToMultiByte(CP_UTF8, 0, language, -1, nullptr, 0, nullptr, nullptr);
                    std::vector<char> utf8Lang(utf8Len);
                    WideCharToMultiByte(CP_UTF8, 0, language, -1, utf8Lang.data(), utf8Len, nullptr, nullptr);
                    voice.language = utf8Lang.data();
                    
                    CoTaskMemFree(language);
                }
            }
            
            // Get voice ID
            WCHAR* id = nullptr;
            if (SUCCEEDED(pVoice->GetId(&id))) {
                int utf8Len = WideCharToMultiByte(CP_UTF8, 0, id, -1, nullptr, 0, nullptr, nullptr);
                std::vector<char> utf8Id(utf8Len);
                WideCharToMultiByte(CP_UTF8, 0, id, -1, utf8Id.data(), utf8Len, nullptr, nullptr);
                voice.id = utf8Id.data();
                
                CoTaskMemFree(id);
            }
        }
        
        return voice;
    }
    
    bool initializeWindows() {
        // Initialize COM
        HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        if (FAILED(hr)) {
            return false;
        }
        
        // Create SAPI voice
        hr = CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_ALL, IID_ISpVoice, (void**)&pSAPI);
        if (FAILED(hr)) {
            CoUninitialize();
            return false;
        }
        
        // Set up event callback for progress tracking
        hr = pSAPI->SetInterest(SPFEI(SPEI_START_INPUT_STREAM) | SPFEI(SPEI_END_INPUT_STREAM) | 
                               SPFEI(SPEI_WORD_BOUNDARY), SPFEI(SPEI_START_INPUT_STREAM) | 
                               SPFEI(SPEI_END_INPUT_STREAM) | SPFEI(SPEI_WORD_BOUNDARY));
        
        if (SUCCEEDED(hr)) {
            isInitialized = true;
            return true;
        }
        
        pSAPI.Release();
        CoUninitialize();
        return false;
    }
    
    void cleanupWindows() {
        if (pSAPI) {
            pSAPI->Speak(nullptr, SPF_PURGEBEFORESPEAK, nullptr);
            pSAPI.Release();
        }
        if (pVoice) {
            pVoice.Release();
        }
        if (pStream) {
            pStream.Release();
        }
        
        if (isInitialized) {
            CoUninitialize();
            isInitialized = false;
        }
    }
    
private:
    CComPtr<ISpVoice> pSAPI;
    CComPtr<ISpObjectToken> pVoice;
    CComPtr<ISpStream> pStream;
    bool isInitialized;
    
    // Callback methods
    void onSpeechStarted() {
        state = SpeechState::Speaking;
        if (speechStartedCallback) {
            speechStartedCallback();
        }
    }
    
    void onSpeechFinished() {
        if (isChunked && currentChunk < chunks.size() - 1) {
            currentChunk++;
            speakCurrentChunk();
        } else {
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
    
    bool speakCurrentChunk() {
        if (isChunked && currentChunk < chunks.size()) {
            return speakWindows(chunks[currentChunk]);
        }
        return false;
    }
};

} // namespace Opra

#endif // _WIN32