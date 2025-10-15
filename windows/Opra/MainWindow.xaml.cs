using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Opra.Shared;
using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using Windows.Storage.Pickers;
using Windows.Storage;

namespace Opra;

public sealed partial class MainWindow : Window, INotifyPropertyChanged
{
    private PDFTextExtractor pdfExtractor = new();
    private TextToSpeech textToSpeech = new();
    private string selectedFilePath = string.Empty;
    private string selectedFileName = string.Empty;
    private int totalPages = 0;
    private int startPage = 1;
    private int endPage = 1;
    private string extractedText = string.Empty;
    private bool hasPDF = false;

    public MainWindow()
    {
        this.InitializeComponent();
        this.Title = "Opra - PDF Reader AI";
        
        // Set up text-to-speech event handlers
        textToSpeech.SpeechStarted += OnSpeechStarted;
        textToSpeech.SpeechFinished += OnSpeechFinished;
        textToSpeech.SpeechPaused += OnSpeechPaused;
        textToSpeech.SpeechResumed += OnSpeechResumed;
        textToSpeech.ProgressChanged += OnProgressChanged;
        
        // Initialize available voices
        AvailableVoices = new ObservableCollection<TextToSpeech.Voice>(textToSpeech.GetAvailableVoices());
        if (AvailableVoices.Count > 0)
        {
            SelectedVoice = AvailableVoices[0];
        }
    }

    // Properties for data binding
    public bool HasPDF
    {
        get => hasPDF;
        set => SetProperty(ref hasPDF, value);
    }

    public string SelectedFileName
    {
        get => selectedFileName;
        set => SetProperty(ref selectedFileName, value);
    }

    public string PageCountText => $"Pages: {totalPages} total";

    public string ExtractedText
    {
        get => extractedText;
        set => SetProperty(ref extractedText, value);
    }

    public Symbol PlayButtonSymbol => textToSpeech.IsSpeaking 
        ? (textToSpeech.IsPaused ? Symbol.Play : Symbol.Pause) 
        : Symbol.Play;

    public bool IsSpeaking => textToSpeech.IsSpeaking;

    public float SpeechRate
    {
        get => textToSpeech.Settings.Rate;
        set
        {
            var settings = textToSpeech.Settings;
            settings.Rate = value;
            textToSpeech.Settings = settings;
            OnPropertyChanged();
        }
    }

    public string SpeedText => $"{(int)(SpeechRate * 100)}%";

    public ObservableCollection<TextToSpeech.Voice> AvailableVoices { get; }

    public TextToSpeech.Voice? SelectedVoice
    {
        get => textToSpeech.GetCurrentVoice();
        set
        {
            if (value != null)
            {
                textToSpeech.SetVoice(value.Id);
                OnPropertyChanged();
            }
        }
    }

    public string StatusText
    {
        get
        {
            if (textToSpeech.IsSpeaking)
            {
                return textToSpeech.IsPaused ? "Paused" : "Speaking...";
            }
            return "Ready";
        }
    }

    public string StatusColor => textToSpeech.IsSpeaking ? "Green" : "Gray";

    public float Progress => textToSpeech.Progress;

    public string ProgressText => textToSpeech.IsSpeaking 
        ? $"{textToSpeech.CurrentWordIndex} of {textToSpeech.TotalWords} words" 
        : string.Empty;

    // Event handlers
    private async void OnSelectPDFClicked(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".pdf");
        
        var window = (Application.Current as App)?.m_window;
        if (window != null)
        {
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
            WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);
        }

        var file = await picker.PickSingleFileAsync();
        if (file != null)
        {
            await LoadPDF(file.Path);
        }
    }

    private void OnSettingsClicked(object sender, RoutedEventArgs e)
    {
        // TODO: Implement settings dialog
        var dialog = new ContentDialog
        {
            Title = "Settings",
            Content = "Settings dialog will be implemented here",
            CloseButtonText = "Close",
            XamlRoot = this.Content.XamlRoot
        };
        _ = dialog.ShowAsync();
    }

    private void OnPlayPauseClicked(object sender, RoutedEventArgs e)
    {
        if (textToSpeech.IsSpeaking)
        {
            if (textToSpeech.IsPaused)
            {
                textToSpeech.Resume();
            }
            else
            {
                textToSpeech.Pause();
            }
        }
        else
        {
            StartSpeaking();
        }
    }

    private void OnStopClicked(object sender, RoutedEventArgs e)
    {
        textToSpeech.Stop();
    }

    private async Task LoadPDF(string filePath)
    {
        try
        {
            selectedFilePath = filePath;
            selectedFileName = System.IO.Path.GetFileName(filePath);
            
            // Extract text from PDF
            var result = pdfExtractor.ExtractText(filePath);
            if (result.Success)
            {
                totalPages = result.PageRange.TotalPages;
                startPage = result.PageRange.StartPage;
                endPage = result.PageRange.EndPage;
                extractedText = result.FullText;
                hasPDF = true;
                
                OnPropertyChanged(nameof(SelectedFileName));
                OnPropertyChanged(nameof(PageCountText));
                OnPropertyChanged(nameof(ExtractedText));
                OnPropertyChanged(nameof(HasPDF));
            }
            else
            {
                // Show error dialog
                var dialog = new ContentDialog
                {
                    Title = "Error",
                    Content = result.ErrorMessage,
                    CloseButtonText = "OK",
                    XamlRoot = this.Content.XamlRoot
                };
                await dialog.ShowAsync();
            }
        }
        catch (Exception ex)
        {
            var dialog = new ContentDialog
            {
                Title = "Error",
                Content = $"Failed to load PDF: {ex.Message}",
                CloseButtonText = "OK",
                XamlRoot = this.Content.XamlRoot
            };
            await dialog.ShowAsync();
        }
    }

    private void StartSpeaking()
    {
        if (!string.IsNullOrEmpty(extractedText))
        {
            textToSpeech.Speak(extractedText);
        }
    }

    // Text-to-speech event handlers
    private void OnSpeechStarted(object? sender, EventArgs e)
    {
        OnPropertyChanged(nameof(PlayButtonSymbol));
        OnPropertyChanged(nameof(IsSpeaking));
        OnPropertyChanged(nameof(StatusText));
        OnPropertyChanged(nameof(StatusColor));
    }

    private void OnSpeechFinished(object? sender, EventArgs e)
    {
        OnPropertyChanged(nameof(PlayButtonSymbol));
        OnPropertyChanged(nameof(IsSpeaking));
        OnPropertyChanged(nameof(StatusText));
        OnPropertyChanged(nameof(StatusColor));
        OnPropertyChanged(nameof(ProgressText));
    }

    private void OnSpeechPaused(object? sender, EventArgs e)
    {
        OnPropertyChanged(nameof(PlayButtonSymbol));
        OnPropertyChanged(nameof(IsSpeaking));
        OnPropertyChanged(nameof(StatusText));
        OnPropertyChanged(nameof(StatusColor));
    }

    private void OnSpeechResumed(object? sender, EventArgs e)
    {
        OnPropertyChanged(nameof(PlayButtonSymbol));
        OnPropertyChanged(nameof(IsSpeaking));
        OnPropertyChanged(nameof(StatusText));
        OnPropertyChanged(nameof(StatusColor));
    }

    private void OnProgressChanged(object? sender, (float Progress, int CurrentWord, int TotalWords) e)
    {
        OnPropertyChanged(nameof(Progress));
        OnPropertyChanged(nameof(ProgressText));
    }

    // INotifyPropertyChanged implementation
    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    private bool SetProperty<T>(ref T backingStore, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(backingStore, value))
            return false;

        backingStore = value;
        OnPropertyChanged(propertyName);
        return true;
    }
}