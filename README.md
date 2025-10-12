# Opra - Open PDF Reader AI

**Opra** is a powerful macOS application that transforms PDF reading into an audio experience using advanced text-to-speech technology. Whether you're studying, researching, or simply prefer listening to content, Opra makes PDF documents accessible through high-quality speech synthesis.

## 🎯 Features

### 📖 **PDF Reading & Navigation**
- **PDF Visualization**: Large, clear PDF viewer with Music app-style interface
- **Page Selection**: Choose specific page ranges to read
- **Vertical Scrolling**: Smooth continuous scrolling for seamless reading
- **Reading Marker**: Visual progress tracking while listening

### 🎙️ **Dual Text-to-Speech Engines**
- **System TTS**: Fast, reliable macOS built-in voices
- **Ollama AI TTS**: High-quality AI-powered speech synthesis
  - Support for Bark, Tortoise-TTS, and Coqui-TTS models
  - Easy model installation and management
  - Superior voice quality and naturalness

### 🎛️ **Advanced Controls**
- **Real-time Speed Control**: Adjust reading speed on the fly
- **Voice Selection**: Choose from available system voices
- **Preview Features**: Test voices and speeds before reading
- **Playback Controls**: Play, pause, resume, and stop functionality

### ⚙️ **Settings & Customization**
- **Persistent Settings**: Save your preferences across sessions
- **Auto-start Reading**: Automatically begin reading after page selection
- **Provider Switching**: Seamlessly switch between TTS engines
- **Comprehensive Settings Panel**: Large, user-friendly configuration interface

## 🚀 Getting Started

### Prerequisites
- macOS 14.0 or later
- Xcode 15.0 or later (for building from source)
- Ollama (optional, for AI TTS features)

### Installation

#### Option 1: Download Pre-built App
1. Download the latest release from the [Releases page](https://github.com/kekko7072/opra/releases)
2. Open the downloaded `.dmg` file
3. Drag Opra to your Applications folder
4. Launch Opra from Applications

#### Option 2: Build from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/kekko7072/opra.git
   cd opra
   ```

2. Open the project in Xcode:
   ```bash
   open Opra.xcodeproj
   ```

3. Build and run the project (⌘+R)

### Ollama AI TTS Setup (Optional)

For enhanced voice quality with AI models:

1. **Install Ollama**:
   - Visit [ollama.ai](https://ollama.ai) and download for macOS
   - Or use the "Open Documentation" button in Opra's settings

2. **Start Ollama**:
   ```bash
   ollama serve
   ```

3. **Install TTS Models**:
   ```bash
   ollama pull bark
   ollama pull tortoise-tts
   ollama pull coqui-tts
   ```

4. **Configure in Opra**:
   - Open Settings (⚙️)
   - Select "Ollama TTS" as your provider
   - Choose your preferred model

## 📱 Usage

### Basic Workflow
1. **Open a PDF**: Click "Select PDF" or use ⌘+O
2. **Choose Pages**: Set start and end pages (optional)
3. **Select Voice**: Choose your preferred TTS provider and voice
4. **Start Reading**: Click the play button or press Space
5. **Follow Along**: Watch the reading marker track your progress

### Keyboard Shortcuts
- `⌘+O`: Open PDF file
- `Space`: Play/Pause reading
- `⌘+S`: Open Settings
- `⌘+Q`: Quit application

### Advanced Features
- **Page Range Selection**: Specify exact pages to read
- **Speed Preview**: Test different reading speeds
- **Voice Preview**: Sample different voices before reading
- **Auto-scroll**: PDF automatically scrolls to follow reading progress

## 🏗️ Architecture

### Core Components
- **OpraApp**: Main application entry point
- **ContentView**: Primary UI and user interactions
- **PDFTextExtractor**: PDF processing and text extraction
- **TTSProviderManager**: Abstraction layer for TTS engines
- **TextToSpeechManager**: System TTS implementation
- **OllamaTTSManager**: AI TTS integration
- **SettingsManager**: User preferences and persistence

### Technology Stack
- **SwiftUI**: Modern, declarative UI framework
- **PDFKit**: PDF document handling and rendering
- **AVFoundation**: Audio playback and speech synthesis
- **Combine**: Reactive programming and data flow
- **Ollama API**: AI model integration via HTTP

## 🔧 Development

### Project Structure
```
Opra/
├── Opra/                    # Main source code
│   ├── OpraApp.swift       # App entry point
│   ├── ContentView.swift   # Main UI
│   ├── PDFTextExtractor.swift
│   ├── TextToSpeechManager.swift
│   ├── OllamaTTSManager.swift
│   ├── TTSProvider.swift
│   ├── SettingsManager.swift
│   └── Opra.entitlements   # App permissions
├── Opra.xcodeproj          # Xcode project
└── README.md
```

### Building
1. Open `Opra.xcodeproj` in Xcode
2. Select your target device/simulator
3. Press ⌘+R to build and run

### Contributing
1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make your changes
4. Commit: `git commit -m "Add feature"`
5. Push: `git push origin feature-name`
6. Open a Pull Request

## 📋 Requirements

### System Requirements
- macOS 14.0 or later
- 8GB RAM (recommended for Ollama TTS)
- 2GB free disk space

### Ollama Requirements (Optional)
- 4GB RAM minimum for TTS models
- 2GB additional disk space per model
- Internet connection for model downloads

## 🐛 Troubleshooting

### Common Issues

**"Could not load PDF" Error**
- Ensure the PDF file is not corrupted
- Check file permissions
- Try opening the PDF in another application first

**Ollama TTS Not Working**
- Verify Ollama is running: `ollama list`
- Check if models are installed: `ollama list`
- Restart Ollama: `ollama serve`

**Audio Not Playing**
- Check system volume
- Verify audio output device
- Try switching TTS providers in settings

### Getting Help
- Check the [Issues](https://github.com/kekko7072/opra/issues) page
- Create a new issue with detailed information
- Include system version and error messages

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Apple**: For PDFKit and AVFoundation frameworks
- **Ollama**: For providing excellent AI model hosting
- **Open Source Community**: For inspiration and contributions

## 🔮 Roadmap

### Upcoming Features
- [ ] Support for more document formats (EPUB, TXT)
- [ ] Cloud storage integration (iCloud, Dropbox)
- [ ] Advanced reading analytics
- [ ] Custom voice training
- [ ] Batch processing capabilities
- [ ] iOS companion app

### Version History
- **v1.0.0**: Initial release with dual TTS support
- **v1.1.0**: Enhanced UI and settings panel
- **v1.2.0**: Ollama integration and AI voices

---

**Opra** - Making PDFs accessible through the power of voice. 🎧📚

*Built with ❤️ for the macOS community*