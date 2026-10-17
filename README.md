# LiveSub — On-Device Real-Time Subtitles & Translation for Android

LiveSub captures audio playback internally (or via microphone) and generates real-time translated subtitles in a floating, movable overlay.

[![Build and Release APK](https://github.com/martinfou/close-caption/actions/workflows/build-apk.yml/badge.svg)](https://github.com/martinfou/close-caption/actions/workflows/build-apk.yml)
[![Latest Release](https://img.shields.io/github/v/release/martinfou/close-caption?label=Latest%20Release)](https://github.com/martinfou/close-caption/releases/latest)

---

## 📥 Download APK

You can download the ready-to-install Android APK directly from GitHub Releases:

👉 **[Download Latest APK (LiveSub-debug.apk)](https://github.com/martinfou/close-caption/releases/latest)**

> **Note on installation:** Since this APK is built directly from GitHub Actions without Play Store signing, Android will ask you to *"Install unknown apps"* or *"Allow from this source"*. You can safely confirm.

---

## ✨ Features

- **Internal Audio Capture:** Captures media & game sound digitally using Android 10+ AudioPlaybackCapture API without ambient noise.
- **Continuous On-Device Speech Recognition:** Powered by Android's built-in `SpeechRecognizer` streaming pipeline.
- **On-Device Translation:** Offline neural machine translation powered by Google ML Kit.
- **Floating Subtitle Pill:** Smooth, draggable overlay with custom background opacity, adjustable font size, and quick collapse/expand modes.
- **Microphone Fallback:** Automatically switches to device microphone if internal capture is not supported or DRM-restricted.
- **Export to .SRT:** Save session subtitles directly into standard SubRip format to share or archive.

---

## 🛠️ Build Locally

```bash
git clone https://github.com/martinfou/close-caption.git
cd close-caption
./gradlew assembleDebug
```

The output APK will be generated at `app/build/outputs/apk/debug/app-debug.apk`.
