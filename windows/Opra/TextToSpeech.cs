using System;
using System.Collections.Generic;
using System.Linq;
using System.Speech.Synthesis;

namespace Opra;

public class TextToSpeech
{
    private readonly SpeechSynthesizer synthesizer;
    private bool isSpeaking = false;
    private bool isPaused = false;
    private float progress = 0;
    private int currentWordIndex = 0;
    private int totalWords = 0;

    public class Voice
    {
        public string Id { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
    }

    public struct SpeechSettings
    {
        public float Rate { get; set; }
        public float Volume { get; set; }
        public float Pitch { get; set; }
    }

    public event EventHandler? SpeechStarted;
    public event EventHandler? SpeechFinished;
    public event EventHandler? SpeechPaused;
    public event EventHandler? SpeechResumed;

    public bool IsSpeaking => isSpeaking;
    public bool IsPaused => isPaused;
    public float Progress => progress;
    public int CurrentWordIndex => currentWordIndex;
    public int TotalWords => totalWords;

    private SpeechSettings settings = new() { Rate = 0.5f, Volume = 1.0f, Pitch = 1.0f };
    public SpeechSettings Settings
    {
        get => settings;
        set
        {
            settings = value;
            // Map 0.1-1.0 range to -10 to +10 for SpeechSynthesizer
            synthesizer.Rate = (int)((value.Rate - 0.5f) * 20);
            synthesizer.Volume = (int)(value.Volume * 100);
        }
    }

    public TextToSpeech()
    {
        synthesizer = new SpeechSynthesizer();
        synthesizer.SetOutputToDefaultAudioDevice();
        
        synthesizer.SpeakStarted += (s, e) =>
        {
            isSpeaking = true;
            SpeechStarted?.Invoke(this, EventArgs.Empty);
        };
        
        synthesizer.SpeakCompleted += (s, e) =>
        {
            isSpeaking = false;
            isPaused = false;
            progress = 0;
            currentWordIndex = 0;
            SpeechFinished?.Invoke(this, EventArgs.Empty);
        };
    }

    public List<Voice> GetAvailableVoices()
    {
        return synthesizer.GetInstalledVoices()
            .Where(v => v.Enabled)
            .Select(v => new Voice
            {
                Id = v.VoiceInfo.Name,
                Name = v.VoiceInfo.Name
            })
            .ToList();
    }

    public Voice? GetCurrentVoice()
    {
        var current = synthesizer.Voice;
        return new Voice
        {
            Id = current.Name,
            Name = current.Name
        };
    }

    public void SetVoice(string voiceId)
    {
        try
        {
            synthesizer.SelectVoice(voiceId);
        }
        catch
        {
            // Voice not found, keep current
        }
    }

    public void Speak(string text)
    {
        if (isSpeaking)
        {
            Stop();
        }

        totalWords = text.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
        currentWordIndex = 0;
        progress = 0;

        isSpeaking = true;
        isPaused = false;
        
        synthesizer.SpeakAsync(text);
    }

    public void Pause()
    {
        if (isSpeaking && !isPaused)
        {
            synthesizer.Pause();
            isPaused = true;
            SpeechPaused?.Invoke(this, EventArgs.Empty);
        }
    }

    public void Resume()
    {
        if (isSpeaking && isPaused)
        {
            synthesizer.Resume();
            isPaused = false;
            SpeechResumed?.Invoke(this, EventArgs.Empty);
        }
    }

    public void Stop()
    {
        if (isSpeaking)
        {
            synthesizer.SpeakAsyncCancelAll();
            isSpeaking = false;
            isPaused = false;
            progress = 0;
            currentWordIndex = 0;
            SpeechFinished?.Invoke(this, EventArgs.Empty);
        }
    }
}

