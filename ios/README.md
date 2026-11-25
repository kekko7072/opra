# Opra for iPhone and iPad

Open `ios/Opra.xcodeproj`, select the shared **Opra** scheme, and run on an iOS 18+ device. For simulator testing use the **Opra Simulator** scheme, which excludes the upstream MLX dependency and explicitly disables Kokoro; System, OpenAI, and remote Ollama remain available. Xcode 26 / Swift 6.2 or later and the Metal compiler component are required by the existing Kokoro/MLX dependencies. Device installation requires an Apple development signing profile for `francesco.vezzani.opra.ios`.

The target compiles the reader, persistence, PDF extraction, and four speech engines directly from `macos/Opra`; the mobile UI lives here. It supports importing PDFs from Files/Open In, library folders and moving documents, saved reading position, page following/highlighting, passage removal/restoration, page skipping, voice selection, speed controls, and sharing exported WAV/MP3 audio. Swipe passages to remove them; long-press library documents to move them to a folder.

System voices work offline. Download the ~330 MB Kokoro model in Settings for on-device neural speech. Kokoro is disabled in the simulator and needs physical-device performance testing. iOS forbids background GPU work: Kokoro stops when the app leaves the foreground and resumes from the saved passage when Play is pressed again. Keep Opra open during Kokoro audio export; use the exported file in another audio app for screen-locked listening.

System/OpenAI/Ollama playback configures background audio, lock-screen play/pause/skip commands, and interruption/headphone-disconnect handling. Network availability and provider latency still affect continuous playback. OpenAI keys are stored in the iOS Keychain; no keys are bundled or copied from the Mac.

For Ollama, enter the URL of a reachable Apple Silicon Mac/server in Settings. The Mac's Ollama service must be configured separately to accept connections from the phone. Prefer a trusted private network or HTTPS; plain HTTP sends document text unencrypted. `localhost` on the phone is not the Mac. Opra's desktop MCP server intentionally remains loopback-only.

The macOS Sparkle updater does not deliver iOS builds. App Store/TestFlight distribution, provisioning, and physical-device listening/battery testing remain separate release steps. There is no cross-device library synchronization in this version.
