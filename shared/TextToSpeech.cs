using System.Speech.Synthesis;
using System.ComponentModel;

namespace Opra.Shared;

public class TextToSpeech : INotifyPropertyChanged
{
    public class Voice
    {
        public string Id { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Language { get; set; } = string.Empty;
        public bool IsDefault { get; set; }
    }

    public class SpeechSettings
    {
        public float Rate { get; set; } = 0.5f;
        public float Pitch { get; set; } = 1.0f;
        public float Volume { get; set; } = 1.0f;
        public string VoiceId { get; set; } = string.Empty;
    }

    public enum SpeechState
    {
        Stopped,
        Speaking,
        Paused
    }

    // Events
    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler? SpeechStarted;
    public event EventHandler? SpeechFinished;
    public event EventHandler? SpeechPaused;
    public event EventHandler? SpeechResumed;
    public event EventHandler<(float Progress, int CurrentWord, int TotalWords)>? ProgressChanged;

    private SpeechSynthesizer? synthesizer;
    private SpeechSettings settings = new();
    private SpeechState state = SpeechState.Stopped;
    private List<string> chunks = new();
    private int currentChunk = 0;
    private bool isChunked = false;
    private float progress = 0.0f;
    private int currentWordIndex = 0;
    private int totalWords = 0;

    public TextToSpeech()
    {
        Initialize();
    }

    ~TextToSpeech()
    {
        Cleanup();
    }

    public SpeechState State
    {
        get => state;
        private set
        {
            if (state != value)
            {
                state = value;
                OnPropertyChanged(nameof(State));
                OnPropertyChanged(nameof(IsSpeaking));
                OnPropertyChanged(nameof(IsPaused));
            }
        }
    }

    public bool IsSpeaking => state == SpeechState.Speaking;
    public bool IsPaused => state == SpeechState.Paused;

    public SpeechSettings Settings
    {
        get => settings;
        set
        {
            settings = value;
            ApplySettings();
            OnPropertyChanged(nameof(Settings));
        }
    }

    public float Progress
    {
        get => progress;
        private set
        {
            if (Math.Abs(progress - value) > 0.01f)
            {
                progress = value;
                OnPropertyChanged(nameof(Progress));
            }
        }
    }

    public int CurrentWordIndex
    {
        get => currentWordIndex;
        private set
        {
            if (currentWordIndex != value)
            {
                currentWordIndex = value;
                OnPropertyChanged(nameof(CurrentWordIndex));
            }
        }
    }

    public int TotalWords
    {
        get => totalWords;
        private set
        {
            if (totalWords != value)
            {
                totalWords = value;
                OnPropertyChanged(nameof(TotalWords));
            }
        }
    }

    public bool Speak(string text)
    {
        if (string.IsNullOrWhiteSpace(text))
            return false;

        Stop(); // Stop any current speech

        var cleanedText = CleanTextForTTS(text);
        if (string.IsNullOrWhiteSpace(cleanedText))
            return false;

        if (synthesizer == null)
            return false;

        try
        {
            synthesizer.SpeakAsync(cleanedText);
            State = SpeechState.Speaking;
            SpeechStarted?.Invoke(this, EventArgs.Empty);
            return true;
        }
        catch
        {
            return false;
        }
    }

    public bool SpeakChunked(List<string> textChunks, int startChunk = 0)
    {
        if (textChunks == null || textChunks.Count == 0 || startChunk >= textChunks.Count)
            return false;

        Stop(); // Stop any current speech

        chunks = textChunks.ToList();
        currentChunk = startChunk;
        isChunked = true;

        return SpeakCurrentChunk();
    }

    public void Pause()
    {
        if (State == SpeechState.Speaking && synthesizer != null)
        {
            synthesizer.Pause();
            State = SpeechState.Paused;
            SpeechPaused?.Invoke(this, EventArgs.Empty);
        }
    }

    public void Resume()
    {
        if (State == SpeechState.Paused && synthesizer != null)
        {
            synthesizer.Resume();
            State = SpeechState.Speaking;
            SpeechResumed?.Invoke(this, EventArgs.Empty);
        }
    }

    public void Stop()
    {
        if (State != SpeechState.Stopped && synthesizer != null)
        {
            synthesizer.SpeakAsyncCancelAll();
        }

        State = SpeechState.Stopped;
        isChunked = false;
        chunks.Clear();
        currentChunk = 0;
        Progress = 0.0f;
        CurrentWordIndex = 0;
        TotalWords = 0;
    }

    public List<Voice> GetAvailableVoices()
    {
        var voices = new List<Voice>();

        if (synthesizer != null)
        {
            foreach (var voice in synthesizer.GetInstalledVoices())
            {
                var voiceInfo = voice.VoiceInfo;
                voices.Add(new Voice
                {
                    Id = voiceInfo.Id,
                    Name = voiceInfo.Name,
                    Language = voiceInfo.Culture.Name,
                    IsDefault = voiceInfo.Name.Contains("Microsoft") && voiceInfo.Name.Contains("Desktop")
                });
            }
        }

        return voices;
    }

    public bool SetVoice(string voiceId)
    {
        if (synthesizer == null)
            return false;

        try
        {
            var voice = synthesizer.GetInstalledVoices().FirstOrDefault(v => v.VoiceInfo.Id == voiceId);
            if (voice != null)
            {
                synthesizer.SelectVoice(voiceId);
                settings.VoiceId = voiceId;
                return true;
            }
        }
        catch
        {
            // Voice not found or error setting voice
        }

        return false;
    }

    public Voice? GetCurrentVoice()
    {
        if (synthesizer?.Voice != null)
        {
            var voiceInfo = synthesizer.Voice;
            return new Voice
            {
                Id = voiceInfo.Id,
                Name = voiceInfo.Name,
                Language = voiceInfo.Culture.Name,
                IsDefault = voiceInfo.Name.Contains("Microsoft") && voiceInfo.Name.Contains("Desktop")
            };
        }

        return null;
    }

    private bool Initialize()
    {
        try
        {
            synthesizer = new SpeechSynthesizer();
            synthesizer.SpeakCompleted += OnSpeakCompleted;
            synthesizer.SpeakProgress += OnSpeakProgress;
            return true;
        }
        catch
        {
            return false;
        }
    }

    private void Cleanup()
    {
        if (synthesizer != null)
        {
            synthesizer.SpeakAsyncCancelAll();
            synthesizer.SpeakCompleted -= OnSpeakCompleted;
            synthesizer.SpeakProgress -= OnSpeakProgress;
            synthesizer.Dispose();
            synthesizer = null;
        }
    }

    private void ApplySettings()
    {
        if (synthesizer == null)
            return;

        try
        {
            // Set rate (convert from 0.0-1.0 to SAPI range -10 to 10)
            int sapiRate = (int)((settings.Rate - 0.5f) * 20.0f);
            sapiRate = Math.Max(-10, Math.Min(10, sapiRate));
            synthesizer.Rate = sapiRate;

            // Set volume (convert from 0.0-1.0 to SAPI range 0-100)
            int sapiVolume = (int)(settings.Volume * 100.0f);
            sapiVolume = Math.Max(0, Math.Min(100, sapiVolume));
            synthesizer.Volume = sapiVolume;

            // Set voice if specified
            if (!string.IsNullOrEmpty(settings.VoiceId))
            {
                SetVoice(settings.VoiceId);
            }
        }
        catch
        {
            // Error applying settings
        }
    }

    private bool SpeakCurrentChunk()
    {
        if (isChunked && currentChunk < chunks.Count)
        {
            return Speak(chunks[currentChunk]);
        }
        return false;
    }

    private void OnSpeakCompleted(object? sender, SpeakCompletedEventArgs e)
    {
        if (isChunked && currentChunk < chunks.Count - 1)
        {
            // Move to next chunk
            currentChunk++;
            _ = Task.Run(() => SpeakCurrentChunk());
        }
        else
        {
            // All chunks finished or single text finished
            State = SpeechState.Stopped;
            isChunked = false;
            chunks.Clear();
            currentChunk = 0;
            SpeechFinished?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnSpeakProgress(object? sender, SpeakProgressEventArgs e)
    {
        if (e.Text.Length > 0)
        {
            // Calculate progress based on character position
            float progress = (float)e.CharacterPosition / e.Text.Length;
            Progress = Math.Max(0.0f, Math.Min(1.0f, progress));

            // Estimate word count for progress tracking
            var wordsUpToPosition = e.Text.Substring(0, e.CharacterPosition)
                .Split(new[] { ' ', '\t', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries);
            var allWords = e.Text.Split(new[] { ' ', '\t', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries);

            CurrentWordIndex = wordsUpToPosition.Length;
            TotalWords = allWords.Length;

            ProgressChanged?.Invoke(this, (Progress, CurrentWordIndex, TotalWords));
        }
    }

    private string CleanTextForTTS(string text)
    {
        if (string.IsNullOrWhiteSpace(text))
            return "No content available for speech synthesis.";

        var cleaned = text;

        // Remove control characters except newlines and tabs
        cleaned = System.Text.RegularExpressions.Regex.Replace(cleaned, @"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]", "");

        // Remove zero-width characters
        cleaned = System.Text.RegularExpressions.Regex.Replace(cleaned, @"[\u200B-\u200D\u2060\uFEFF]", "");

        // Replace problematic Unicode spaces with regular spaces
        cleaned = System.Text.RegularExpressions.Regex.Replace(cleaned, @"[\u00A0\u2000-\u200F\u2028-\u202F\u205F-\u206F\u3000]", " ");

        // Clean up multiple spaces
        cleaned = System.Text.RegularExpressions.Regex.Replace(cleaned, @"\s{2,}", " ");

        // Trim whitespace
        cleaned = cleaned.Trim();

        return string.IsNullOrWhiteSpace(cleaned) ? "No content available for speech synthesis." : cleaned;
    }

    protected virtual void OnPropertyChanged(string propertyName)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}