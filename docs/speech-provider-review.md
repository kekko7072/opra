# Speech provider and platform review — October 26, 2026

## Implemented in this change

| Provider | Improvement |
| --- | --- |
| Ollama / Phonon | New local Apple Silicon provider, setup guidance, version/capability check, dynamic voices, persistent voice choice, preview, chunked PCM-to-WAV playback and actionable failures. |
| OpenAI | Model-aware voice selection prevents sending `marin`/`cedar` to legacy models; unsupported style instructions are omitted. Bounded Unicode-aware splitting also handles unusually long PDF tokens. |
| Kokoro | Require the checked 1.0.11 release; keep its required MLX 0.30.2 / MLXUtilsLibrary 0.0.6 dependency pair. Persist voice selection and remove main-thread mutation of the inference queue's voice cache. Bound every synthesis request, including long unbroken tokens. |
| System (macOS) | Cancel pending delayed starts on stop/provider change and ignore callbacks from superseded utterances. Clamp passage start indices. |
| Shared audio playback | Ignore obsolete player callbacks after stop/skip/replacement; preflight failures cancel active work before displaying errors. |

The existing default provider remains Kokoro where supported. Ollama is opt-in, uses the default English 31M Phonon model, and never downloads models or falls back to a cloud provider automatically.

## Upstream updates requiring separate migrations

### OpenAI: migrate before January 6, 2027

OpenAI's [deprecations page](https://developers.openai.com/api/docs/deprecations) and [TTS guide](https://developers.openai.com/api/docs/guides/text-to-speech) announce retirement of `tts-1`, `tts-1-hd`, and `gpt-4o-mini-tts` (including dated snapshots) on January 6, 2027. The recommended replacement is `gpt-realtime-2.1-mini` through the Realtime API. **It is not compatible with the current `/v1/audio/speech` request.**

This change repairs the existing Speech API integration while it is still supported. It does not claim to complete that migration. A follow-up needs session/event handling, audio deltas, cancellation, voice mapping, and narration-fidelity tests to ensure PDF text is read verbatim rather than answered or paraphrased. Validate pricing and account availability before changing defaults.

### Kokoro: compatible dependency set and timing support

The checked upstream [1.0.11 manifest](https://github.com/mlalma/kokoro-ios/blob/1.0.11/Package.swift) requires Swift 6.2, MLX **0.30.2**, MisakiSwift **1.0.6**, and MLXUtilsLibrary **0.0.6**. Opra already pins the two shared MLX dependencies to these versions; independently upgrading them would conflict with Kokoro's exact requirements.

The [upstream README](https://github.com/mlalma/kokoro-ios) describes token timestamps introduced in 1.0.8. Opra currently ignores the returned alignment data. Using it for precise word highlighting is a separate improvement; the shared controller currently estimates word progress from duration. No synthesis-speed improvement is claimed without device benchmarks.

### Windows: scaffold modernization before shipping

The Windows project still targets .NET 8 and Windows App SDK 1.6.240923002. Microsoft's [.NET lifecycle notice](https://devblogs.microsoft.com/dotnet/dotnet-8-9-end-of-support/) sets .NET 8 end of support to **November 10, 2026** and recommends .NET 10 LTS. The [Windows App SDK lifecycle table](https://learn.microsoft.com/windows/apps/windows-app-sdk/release-channels) lists 1.6 as out of support since **September 4, 2025**.

Before shipping, migrate the WinUI project and its build tooling to a supported SDK/runtime pair and validate System.Speech, PDF extraction, packaging and signing on Windows. This is a non-shipping scaffold, not a second production app updated by this patch. No Windows or Linux Ollama speech support is enabled: [Ollama's model page](https://ollama.com/library/phonon) currently requires Apple Silicon, and this repository has no Linux app.

## Validation

`bash scripts/test-speech.sh` compiles and runs offline tests against the actual Foundation support files. It covers long documents and Unicode tokens, exact word offsets, PCM/WAV headers and payloads, voice compatibility, numeric version comparisons, voice discovery, request payloads, HTTP errors, unavailable Ollama, malformed/empty audio, and cancellation. It needs no API key, installed model, or audio device. CI runs it before the macOS app build.

Manual Apple Silicon acceptance checks remain necessary:

1. Install Ollama 0.40.11+, pull Phonon, check connection, select a catalog voice, and preview it.
2. Read a multi-page PDF; pause/resume, skip passages, change speed, and switch providers during generation/playback. Confirm obsolete audio never restarts.
3. Restart Opra and verify Ollama and Kokoro voice preferences persist.
4. Stop Ollama, remove Phonon, and use an unavailable voice; verify errors and recovery.
5. Check System, OpenAI and Kokoro playback on supported Macs, including Intel fallbacks.
6. Verify the sandboxed build can reach localhost and has no broader ATS exception.

The Linux editing workspace has no Swift/Xcode toolchain and cannot validate macOS UI, audio playback, or MLX inference. GitHub rejected branch/commit creation for the connected integration (HTTP 403), so no pull request or CI run was created. Swift tests, the native build, and device acceptance checks have not run. Patch applicability, whitespace, plist parsing and project source membership were checked locally.
