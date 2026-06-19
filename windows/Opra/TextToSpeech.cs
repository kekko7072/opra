using System;
using System.Collections.Generic;
using System.Linq;
using System.Speech.Synthesis;
using System.Text.RegularExpressions;

namespace Opra;

public class TextToSpeech
{
    private readonly SpeechSynthesizer synthesizer;
    private bool isSpeaking = false;
    private bool isPaused = false;
    private float progress = 0;
    private int currentWordIndex = 0;
    private int totalWords = 0;
    private string currentText = string.Empty;
    private int currentTextLength = 1;
    private Prompt? currentPrompt;
    private static readonly Regex WordRegex = new(@"\S+", RegexOptions.Compiled);

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
    public event EventHandler? ProgressChanged;

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

        synthesizer.SpeakProgress += (s, e) =>
        {
            if (currentPrompt != null && e.Prompt != currentPrompt)
            {
                return;
            }

            var characterEnd = Math.Min(currentTextLength, e.CharacterPosition + e.CharacterCount);
            progress = Math.Clamp(characterEnd / (float)currentTextLength, 0f, 1f);

            var wordsBefore = CountWordsBefore(currentText, e.CharacterPosition);
            currentWordIndex = Math.Min(totalWords, wordsBefore + 1);
            ProgressChanged?.Invoke(this, EventArgs.Empty);
        };
        
        synthesizer.SpeakCompleted += (s, e) =>
        {
            if (currentPrompt != null && e.Prompt != currentPrompt)
            {
                return;
            }

            currentPrompt = null;
            isSpeaking = false;
            isPaused = false;
            progress = e.Cancelled ? 0 : 1;
            currentWordIndex = e.Cancelled ? 0 : totalWords;
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

        currentText = NormalizeText(text);
        currentTextLength = Math.Max(1, currentText.Length);
        totalWords = WordRegex.Matches(currentText).Count;
        currentWordIndex = 0;
        progress = 0;

        isSpeaking = true;
        isPaused = false;
        
        currentPrompt = synthesizer.SpeakAsync(currentText);
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
            currentPrompt = null;
            isSpeaking = false;
            isPaused = false;
            progress = 0;
            currentWordIndex = 0;
            SpeechFinished?.Invoke(this, EventArgs.Empty);
        }
    }

    private static string NormalizeText(string text)
    {
        return Regex.Replace(text, @"\s+", " ").Trim();
    }

    private static int CountWordsBefore(string text, int characterPosition)
    {
        if (characterPosition <= 0)
        {
            return 0;
        }

        var safePosition = Math.Min(characterPosition, text.Length);
        return WordRegex.Matches(text[..safePosition]).Count;
    }
}
