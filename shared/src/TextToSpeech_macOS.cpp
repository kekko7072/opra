#ifdef __APPLE__

#include "TextToSpeech.h"
#include <AVFoundation/AVFoundation.h>
#include <Foundation/Foundation.h>

namespace Opra {

bool TextToSpeech::Impl::speakMacOS(const std::string& text) {
    @autoreleasepool {
        NSString* nsText = [NSString stringWithUTF8String:text.c_str()];
        
        // Create AVSpeechUtterance
        AVSpeechUtterance* utterance = [AVSpeechUtterance speechUtteranceWithString:nsText];
        
        // Set voice if specified
        if (!settings.voiceId.empty()) {
            NSString* voiceId = [NSString stringWithUTF8String:settings.voiceId.c_str()];
            AVSpeechSynthesisVoice* voice = [AVSpeechSynthesisVoice voiceWithIdentifier:voiceId];
            if (voice) {
                utterance.voice = voice;
            }
        }
        
        // Set rate (convert from 0.0-1.0 to AVSpeechUtterance range)
        float avRate = AVSpeechUtteranceMinimumSpeechRate + 
                      (settings.rate * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate));
        utterance.rate = avRate;
        
        // Set pitch
        utterance.pitchMultiplier = settings.pitch;
        
        // Set volume
        utterance.volume = settings.volume;
        
        // Create synthesizer if needed
        if (!synthesizer) {
            synthesizer = [[AVSpeechSynthesizer alloc] init];
            synthesizer.delegate = (id<AVSpeechSynthesizerDelegate>)delegate;
        }
        
        // Speak
        [synthesizer speakUtterance:utterance];
        
        onSpeechStarted();
        return true;
    }
}

void TextToSpeech::Impl::pauseMacOS() {
    @autoreleasepool {
        if (synthesizer) {
            [synthesizer pauseSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        }
    }
}

void TextToSpeech::Impl::resumeMacOS() {
    @autoreleasepool {
        if (synthesizer) {
            [synthesizer continueSpeaking];
        }
    }
}

void TextToSpeech::Impl::stopMacOS() {
    @autoreleasepool {
        if (synthesizer) {
            [synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        }
    }
}

void TextToSpeech::Impl::setSettingsMacOS(const SpeechSettings& settings) {
    this->settings = settings;
}

std::vector<TextToSpeech::Voice> TextToSpeech::Impl::getAvailableVoicesMacOS() const {
    @autoreleasepool {
        std::vector<Voice> voices;
        NSArray<AVSpeechSynthesisVoice*>* avVoices = [AVSpeechSynthesisVoice speechVoices];
        
        for (AVSpeechSynthesisVoice* avVoice in avVoices) {
            Voice voice;
            voice.id = [avVoice.identifier UTF8String];
            voice.name = [avVoice.name UTF8String];
            voice.language = [avVoice.language UTF8String];
            voice.isDefault = [avVoice isDefault];
            voices.push_back(voice);
        }
        
        return voices;
    }
}

bool TextToSpeech::Impl::setVoiceMacOS(const std::string& voiceId) {
    @autoreleasepool {
        NSString* nsVoiceId = [NSString stringWithUTF8String:voiceId.c_str()];
        AVSpeechSynthesisVoice* voice = [AVSpeechSynthesisVoice voiceWithIdentifier:nsVoiceId];
        return voice != nil;
    }
}

TextToSpeech::Voice TextToSpeech::Impl::getCurrentVoiceMacOS() const {
    @autoreleasepool {
        Voice voice;
        if (synthesizer && synthesizer.voice) {
            voice.id = [synthesizer.voice.identifier UTF8String];
            voice.name = [synthesizer.voice.name UTF8String];
            voice.language = [synthesizer.voice.language UTF8String];
            voice.isDefault = [synthesizer.voice isDefault];
        }
        return voice;
    }
}

bool TextToSpeech::Impl::initializeMacOS() {
    @autoreleasepool {
        synthesizer = [[AVSpeechSynthesizer alloc] init];
        delegate = [[TTSDelegate alloc] initWithImpl:this];
        synthesizer.delegate = (id<AVSpeechSynthesizerDelegate>)delegate;
        return synthesizer != nil;
    }
}

void TextToSpeech::Impl::cleanupMacOS() {
    @autoreleasepool {
        if (synthesizer) {
            [synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
            synthesizer = nil;
        }
        delegate = nil;
    }
}

// TTS Delegate for macOS
@interface TTSDelegate : NSObject <AVSpeechSynthesizerDelegate>
@property (nonatomic, assign) Opra::TextToSpeech::Impl* impl;
- (instancetype)initWithImpl:(Opra::TextToSpeech::Impl*)impl;
@end

@implementation TTSDelegate

- (instancetype)initWithImpl:(Opra::TextToSpeech::Impl*)impl {
    self = [super init];
    if (self) {
        _impl = impl;
    }
    return self;
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didStartSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (self.impl) {
        self.impl->onSpeechStarted();
    }
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (self.impl) {
        self.impl->onSpeechFinished();
    }
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didPauseSpeechUtterance:(AVSpeechUtterance *)utterance {
    // Handle pause if needed
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didContinueSpeechUtterance:(AVSpeechUtterance *)utterance {
    // Handle resume if needed
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer willSpeakRangeOfSpeechString:(NSRange)characterRange utterance:(AVSpeechUtterance *)utterance {
    // Calculate progress based on character range
    if (self.impl && utterance.speechString.length > 0) {
        float progress = (float)characterRange.location / (float)utterance.speechString.length;
        
        // Estimate word count for progress tracking
        NSString* textUpToRange = [utterance.speechString substringToIndex:characterRange.location];
        NSArray* words = [textUpToRange componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        
        NSArray* allWords = [utterance.speechString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        allWords = [allWords filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        
        self.impl->onProgress(progress, (int)words.count, (int)allWords.count);
    }
}

@end

} // namespace Opra

#endif // __APPLE__