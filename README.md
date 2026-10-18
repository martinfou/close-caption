# LiveSub — On-Device Real-Time Subtitles & Translation (iOS & Android)

> **LiveSub** captures playback audio internally (or via microphone fallback) and displays continuous, real-time translated subtitles in a cinematic, floating overlay on top of any video, game, or stream.

<div align="center">

[![Build and Release APK](https://github.com/martinfou/live-sub/actions/workflows/build-apk.yml/badge.svg)](https://github.com/martinfou/live-sub/actions/workflows/build-apk.yml)
[![Latest Release](https://img.shields.io/github/v/release/martinfou/live-sub?label=Latest%20Release&color=00E5FF)](https://github.com/martinfou/live-sub/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

### 📥 [Download Ready-to-Install APK (GitHub Releases)](https://github.com/martinfou/live-sub/releases/latest)
### 🌐 [LiveSub Product Landing Page & Beta Waitlist](https://martinfou.github.io/live-sub/)

</div>

---

## 📸 Screenshots

### 🍎 iOS & iPadOS (Picture-in-Picture Floating Subtitles)

<div align="center">

| 🎬 Real-Time Translation Over YouTube (PiP HUD) | ⚙️ LiveSub iOS & iPadOS Dashboard |
| :---: | :---: |
| <img src="docs/images/ios_livesub_ipad.png" alt="LiveSub floating PiP translating YouTube video into French" width="380"/> | <img src="docs/images/ios_livesub_dashboard.png" alt="LiveSub iOS Dashboard with Spoken Audio and Subtitle language selectors" width="380"/> |
| *Floating Picture-in-Picture HUD translating English YouTube podcast audio into French in real-time with dual-line display* | *Language selector (`🇺🇸 ⇄ 🇫🇷`), on-device offline download controls, and live audio packet diagnostics* |

</div>

### 🤖 Android (System Floating Pill Overlay)

<div align="center">

| 🎬 Real-time Translation Overlay (YouTube / Streaming) | ⚙️ Language Pair & Service Dashboard |
| :---: | :---: |
| <img src="docs/images/overlay_in_action.png" alt="Overlay in Action over YouTube video" width="340"/> | <img src="docs/images/app_settings.png" alt="LiveSub Dashboard and Language Pair selector" width="340"/> |
| *Floating pill translating German to French over YouTube playback with zero audio stutter* | *On-device setup, offline translation model status, and live audio indicator* |

</div>

---

## ✨ Key Features

- **🎧 Internal Audio Capture via ReplayKit Broadcast (iOS) & AudioPlaybackCapture (Android):** Captures high-fidelity internal digital PCM streams without ambient noise or requiring loud speaker output.
- **⚡ Continuous On-Device Speech Recognition:** Streams speech segments directly into Apple SFSpeechRecognizer and Android Speech Recognition with automatic sentence finalization.
- **🌐 100% On-Device Neural Translation:**
  - **iOS:** Powered by Apple's native `Translation.framework` (iOS 17.4+ / iOS 18+) with offline model pack downloads and ultra-fast network fallback.
  - **Android:** Powered by Google ML Kit Translate with offline neural models.
- **💊 Floating Overlay Subtitles:**
  - **iOS:** Native Picture-in-Picture (`AVPictureInPictureVideoCallViewController`) floating HUD that stays active over YouTube, Netflix, Podcasts, or any application.
  - **Android:** Hardware-accelerated system window overlay (`WindowManager`) draggable anywhere across display boundaries.
- **🔄 Dual-Language Display:** Prominently highlights translated text in bold, with optional original spoken speech displayed underneath.
- **🎤 Microphone Fallback:** Test via hardware microphone with one tap or fallback if internal media capture is restricted.
- **📝 SubRip (.SRT) Export:** Automatically tracks and exports session subtitle history into timestamped `.srt` files.

---

## 🛠️ Build & Run

### 🍎 iOS / iPadOS Project

#### Prerequisites
- macOS Sonoma / Sequoia
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```bash
cd ios

# Generate Xcode project
xcodegen generate

# Build for Simulator
xcodebuild -project LiveSub.xcodeproj -scheme LiveSub -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Or deploy to connected iPad / iPhone
xcodebuild -project LiveSub.xcodeproj -scheme LiveSub -destination 'id=<DEVICE_UDID>' -allowProvisioningUpdates build
```

---

### 🤖 Android Project

#### Prerequisites
- Android Studio Ladybug / Meerkat or Command-Line Tools
- Android SDK 35 (minSdk 29, targetSdk 35)
- JDK 17

```bash
# Run unit tests
./gradlew testDebugUnitTest

# Assemble debug APK
./gradlew assembleDebug
```

The compiled APK will be located at:
```
app/build/outputs/apk/debug/app-debug.apk
```

---

## 🏗️ Architecture & Technical Specifications

LiveSub implements a modular, reactive streaming architecture optimized for sub-second latency on both platforms.

---

### 🍎 iOS & iPadOS Architecture

On iOS, audio capture must bypass sandbox isolation between the ReplayKit extension process and the main app runtime. LiveSub employs a local TCP loopback IPC mechanism with zero-copy stream processing.

```mermaid
flowchart TD
    subgraph MediaLayer["1. Audio Generation & Capture"]
        Media["System Media Playback\n(YouTube, Safari, Netflix, Apps)"]
        Mic["Microphone Fallback\n(AVAudioEngine / 16kHz Mono)"]
        Ext["LiveSubBroadcast Extension\n(RPBroadcastSampleHandler)"]
        Media -->|"ReplayKit audioApp\n44.1kHz Stereo Int16"| Ext
    end

    subgraph IPCLayer["2. Inter-Process Communication (IPC)"]
        ExtClient["AudioSocketClient\n(Network.framework / NWConnection)"]
        TCP["TCP Loopback Socket\n(127.0.0.1:19834)"]
        AppServer["AudioSocketServer\n(NWListener / Dispatch Queue)"]
        
        Ext -->|"Big-Endian to Little-Endian\nStereo downmixed to Mono"| ExtClient
        ExtClient -->|"4-byte Len + ASBD + Int16 Payload"| TCP
        TCP --> AppServer
    end

    subgraph ProcessingLayer["3. Pipeline & ML Engines"]
        PCMUtils["AudioPCMUtils\n(Int16 to Float32 AVAudioPCMBuffer)"]
        ASR["SpeechRecognizer\n(Apple SFSpeechRecognizer / Locale Aware)"]
        KeepAlive["BackgroundKeepAlive\n(AVAudioPlayer Silent Loop / .mixWithOthers)"]
        TransMgr["TranslationManager\n(LanguageAvailability Check & Throttled Queue)"]
        AppleTrans["Apple TranslationSession\n(iOS 18+ On-Device Neural Models)"]
        OnlineFallback["Google GTX API\n(Online Fallback Engine)"]

        AppServer --> PCMUtils
        PCMUtils --> ASR
        Mic -.-> ASR
        KeepAlive -.->|"Prevents App Suspension"| AppServer
        ASR -->|"Continuous Streaming Text"| TransMgr
        TransMgr -->|"On-Device Priority"| AppleTrans
        TransMgr -.->|"Network Fallback"| OnlineFallback
    end

    subgraph PresentationLayer["4. UI & Floating Overlay"]
        TransMgr -->|"Translated Subtitles"| SubtitleOverlay["SubtitleOverlayView\n(Dual-Language Display)"]
        PiPMgr["PiPManager\n(AVPictureInPictureVideoCallViewController)"]
        MainUI["LiveSub App Dashboard\n(SwiftUI / Native Inset Grouped)"]

        PiPMgr -->|"Renders floating HUD"| SubtitleOverlay
        MainUI -->|"Controls, Language Pair, Diagnostics"| TransMgr
    end

    classDef media fill:#1E293B,stroke:#64748B,stroke-width:1px,color:#fff;
    classDef ipc fill:#0F172A,stroke:#38BDF8,stroke-width:2px,color:#fff;
    classDef engine fill:#1A2333,stroke:#818CF8,stroke-width:2px,color:#fff;
    classDef ui fill:#092635,stroke:#2DD4BF,stroke-width:2px,color:#fff;

    class Media,Mic,Ext media;
    class ExtClient,TCP,AppServer ipc;
    class PCMUtils,ASR,KeepAlive,TransMgr,AppleTrans,OnlineFallback engine;
    class SubtitleOverlay,PiPMgr,MainUI ui;
```

#### Key iOS Components
- **`LiveSubBroadcast` (`LiveSubBroadcast/AudioSocketClient.swift`):** ReplayKit extension handling system audio buffers. Detects big-endian 44.1 kHz audio, byte-swaps, and downmixes to mono before streaming over TCP.
- **`AudioSocketServer` (`LiveSub/IPC/AudioSocketServer.swift`):** High-throughput, non-blocking TCP server using Apple's `Network.framework` running on loopback port `19834`.
- **`BackgroundKeepAlive` (`LiveSub/App/BackgroundKeepAlive.swift`):** Silent looping audio background worker configured with `AVAudioSessionCategoryPlayback` and `.mixWithOthers` ensuring the socket server remains active while backgrounded.
- **`TranslationManager` (`LiveSub/Translation/TranslationManager.swift`):** Manages multi-language translation. Inspects `LanguageAvailability` for offline model pack status, streams text via `TranslationSession`, and falls back dynamically to online translation if the on-device model is unavailable.
- **`PiPManager` (`LiveSub/PiP/PiPManager.swift`):** Picture-in-Picture manager leveraging `AVPictureInPictureVideoCallViewController` to render a system-wide floating subtitle HUD.

---

### 🤖 Android Architecture

On Android, audio capture uses the `AudioPlaybackCapture` API backed by a Foreground Service, running directly in-process with hardware-accelerated overlays.

```mermaid
flowchart TD
    subgraph AudioCaptureLayer["1. System Media Capture"]
        Media["Media Audio Playback\n(ExoPlayer, Spotify, YouTube)"]
        Projection["MediaProjection Token\n(AudioPlaybackCaptureConfiguration)"]
        AudioRecord["AudioRecord Streaming\n(16kHz, 16-bit Mono PCM)"]

        Media --> Projection
        Projection --> AudioRecord
    end

    subgraph ServiceLayer["2. Audio & Ring Buffer Processing"]
        CaptureService["AudioCaptureService\n(Foreground Service + Notification)"]
        RingBuffer["AudioRingBuffer\n(Thread-Safe Circular Buffer)"]
        VAD["VadFilter\n(Voice Activity Detection / Energy Gate)"]

        AudioRecord --> CaptureService
        CaptureService --> RingBuffer
        RingBuffer --> VAD
    end

    subgraph MLPipeline["3. ASR & Neural Translation"]
        StreamingASR["StreamingAsrProcessor\n(Chunk Aggregator & Finalizer)"]
        ASREngine["AndroidSpeechRecognizerEngine\n(On-Device Speech Recognition)"]
        MLKit["MlKitTranslationEngine\n(Google ML Kit Translate)"]
        ModelMgr["RemoteModelManager\n(Offline Neural Pack Downloader)"]

        VAD -->|"Filtered Audio Chunks"| StreamingASR
        StreamingASR --> ASREngine
        ASREngine -->|"Recognized Text"| MLKit
        ModelMgr -.->|"Preloaded Offline Models"| MLKit
    end

    subgraph PresentationOverlay["4. Display & Export Layer"]
        OverlayService["OverlayService\n(WindowManager Floating View)"]
        FloatingView["Floating Subtitle Pill\n(Draggable & Auto-hiding)"]
        Exporter["SubtitleHistoryExporter\n(Timestamped .SRT Generator)"]

        MLKit -->|"Translated Text"| OverlayService
        OverlayService --> FloatingView
        ASREngine -->|"Source Text"| Exporter
        MLKit -->|"Target Text"| Exporter
    end

    classDef androidCapture fill:#143026,stroke:#34D399,stroke-width:1px,color:#fff;
    classDef androidService fill:#102A43,stroke:#627D98,stroke-width:2px,color:#fff;
    classDef androidML fill:#241442,stroke:#A78BFA,stroke-width:2px,color:#fff;
    classDef androidUI fill:#2D1B36,stroke:#F472B6,stroke-width:2px,color:#fff;

    class Media,Projection,AudioRecord androidCapture;
    class CaptureService,RingBuffer,VAD androidService;
    class StreamingASR,ASREngine,MLKit,ModelMgr androidML;
    class OverlayService,FloatingView,Exporter androidUI;
```

#### Key Android Components
- **`AudioPlaybackCaptureHelper` (`audio/AudioPlaybackCaptureHelper.kt`):** Configures `AudioPlaybackCaptureConfiguration` matching `USAGE_MEDIA`, `USAGE_GAME`, and `USAGE_UNKNOWN`.
- **`AudioCaptureService` (`audio/AudioCaptureService.kt`):** Foreground service with `mediaProjection` foreground service type hosting the audio capture loop and ring buffer.
- **`VadFilter` (`audio/VadFilter.kt`):** Energy-based Voice Activity Detection filtering ambient silence and background noise before feeding the recognizer.
- **`MlKitTranslationEngine` (`ml/MlKitTranslationEngine.kt`):** Handles on-device neural translation using Google ML Kit with automatic offline model download and lifecycle management.
- **`OverlayService` (`overlay/OverlayService.kt`):** System overlay drawing a responsive, touch-draggable floating pill using `WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY`.

---

## 📜 License

This project is licensed under the MIT License.
