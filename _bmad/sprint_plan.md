# Sprint Plan: LiveSub (Android Native)

## Sprint Goal
Deliver a fully functional, production-ready Android Native application in Kotlin + Jetpack Compose capable of capturing internal digital audio (with mic fallback), performing on-device real-time transcription and translation, and rendering a draggable, customizable floating subtitle overlay over any video playback.

---

## Epics & Stories

### 🚀 Epic 1: Android Project Scaffolding & Core Architecture
- **Status:** Done
- **Description:** Initialize Gradle build scripts, AndroidManifest with foreground service permissions, and domain models.
- **Stories:**
  - [x] **Story 1.1:** Configure Gradle build scripts (`settings.gradle.kts`, `build.gradle.kts`, `app/build.gradle.kts`) with Jetpack Compose, Coroutines, ML Kit, and test dependencies.
  - [x] **Story 1.2:** Configure `AndroidManifest.xml` with `SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE`, `RECORD_AUDIO`, `MEDIA_PROJECTION`, and application entry points.
  - [x] **Story 1.3:** Implement core domain models (`AudioChunk`, `SubtitleItem`, `SubtitleUiState`, `LanguagePair`).

---

### 🎙️ Epic 2: Real-Time Audio Capture & Processing Pipeline
- **Status:** Done
- **Description:** Implement lock-free circular audio ring buffer, foreground capture service with MediaProjection, VAD, and mic fallback.
- **Stories:**
  - [x] **Story 2.1:** Implement high-performance `AudioRingBuffer` for 16kHz PCM streaming.
  - [x] **Story 2.2:** Implement `AudioCaptureService` with `AudioPlaybackCaptureConfiguration` and `MediaProjection` token management.
  - [x] **Story 2.3:** Implement `VadFilter` and automatic DRM silence fallback to physical microphone.

---

### 🤖 Epic 3: On-Device AI Transcription & Translation Pipeline
- **Status:** To Do
- **Description:** Streaming ASR transcription and on-device neural machine translation.
- **Stories:**
  - [ ] **Story 3.1:** Implement `AsrEngine` interface and streaming speech-to-text processor.
  - [ ] **Story 3.2:** Implement `TranslationEngine` interface and `MlKitTranslationEngine` for on-device translation.
  - [ ] **Story 3.3:** Implement `ModelManager` for offline language pack verification and download status.

---

### 📺 Epic 4: Floating Window Overlay (Compose & WindowManager)
- **Status:** To Do
- **Description:** Draggable, customizable floating overlay rendering translated subtitles over any app.
- **Stories:**
  - [ ] **Story 4.1:** Implement `SubtitleOverlayService` with `WindowManager` `TYPE_APPLICATION_OVERLAY` and ComposeView.
  - [ ] **Story 4.2:** Implement `SubTitlePill` Compose UI with drag-and-drop, pinch-to-zoom font scaling, and cinematic opacity styling.
  - [ ] **Story 4.3:** Implement Screen Orientation & Safe Area listener for seamless portrait ↔ landscape transitions.

---

### 📱 Epic 5: Main Application UI & Subtitle Export
- **Status:** To Do
- **Description:** User onboarding, permission checks, language selector, and .srt export.
- **Stories:**
  - [ ] **Story 5.1:** Implement `MainActivity` & `MainScreen` in Jetpack Compose.
  - [ ] **Story 5.2:** Implement `SrtExporter` to format and save timestamped `.srt` files.

---

### 🧪 Epic 6: Automated Verification & Unit Tests
- **Status:** To Do
- **Description:** Unit tests, latency benchmarks, and mock end-to-end audio pipeline verification.
- **Stories:**
  - [ ] **Story 6.1:** Unit tests for `AudioRingBufferTest`, `VadFilterTest`, and `SrtExporterTest`.
  - [ ] **Story 6.2:** Pipeline integration test `AudioPipelineSimulationTest`.
