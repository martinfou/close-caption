# 📱 LiveSub for iOS

Real-time, on-device closed captioning and floating subtitles for any audio playing on iPhone (YouTube, TikTok, Netflix, Spotify, podcasts).

---

## 🏗️ Architecture

```
[System Media (YouTube, TikTok)]
               │
               ▼ (ReplayKit audioApp stream)
┌──────────────────────────────────────────────┐
│  LiveSubBroadcast (Extension, < 50MB RAM)    │
│  - SampleHandler.swift                       │
│  - AudioSocketClient.swift                   │
└──────────────────────┬───────────────────────┘
                       │ UNIX Domain Socket (audio_stream.sock)
                       │ inside App Group (group.com.livesub.app)
                       ▼
┌──────────────────────────────────────────────┐
│  LiveSub (Main SwiftUI App)                  │
│  - AudioSocketServer.swift                   │
│  - SpeechRecognizer.swift (Neural Engine)    │
│  - PiPManager.swift (AVKit VideoCall PiP)    │
│  - SubtitleOverlayView.swift (Floating HUD)  │
└──────────────────────────────────────────────┘
```

1. **Audio Capture**: A ReplayKit Broadcast Upload Extension (`RPBroadcastSampleHandler`) intercepts internal device audio (`.audioApp`) without video to respect the strict 50 MB memory limit.
2. **IPC Channel**: Streams raw 16-bit linear PCM audio over a lightweight Unix Domain Socket inside a shared App Group container (`group.com.livesub.app`).
3. **On-Device AI Transcription**: The main application feeds incoming PCM data into Apple's `SFSpeechRecognizer` (`requiresOnDeviceRecognition = true`) for zero-latency, private offline speech-to-text.
4. **Floating Subtitle Window**: Projects a SwiftUI overlay view into a native Picture-in-Picture window via `AVPictureInPictureVideoCallViewController`.

---

## 🚀 How to Open and Run

### 1. Open in Xcode
```bash
open /Volumes/T7/src/live-sub/ios/LiveSub.xcodeproj
```

### 2. Configure Signing in Xcode
1. In Xcode, click on the **LiveSub** project in the left navigator.
2. Under **TARGETS**, select **LiveSub**:
   - Go to **Signing & Capabilities**.
   - Select your **Personal Team** in the **Team** dropdown.
   - Ensure the **App Groups** capability shows `group.com.livesub.app` (checked).
3. Under **TARGETS**, select **LiveSubBroadcast**:
   - Go to **Signing & Capabilities**.
   - Select the same **Team**.
   - Ensure `group.com.livesub.app` is checked.

### 3. Build & Run
- Connect your physical iPhone (or select an iOS Simulator).
- Select the **LiveSub** scheme.
- Press **Cmd + R** to run!

---

## 🎯 How to Use on Device

1. Open **LiveSub**.
2. Tap the blue **Broadcast button** &rarr; Select **LiveSub Broadcast** &rarr; Tap **Start Broadcast**.
3. Tap **Open Floating Subtitles (PiP)**.
4. Swipe home and open **YouTube**, **TikTok**, or any media app.
5. The floating glassmorphic subtitle card will display live captions over your video in real time!
