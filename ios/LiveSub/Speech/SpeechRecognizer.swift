//
//  SpeechRecognizer.swift
//  LiveSub
//
import Foundation
import Speech
import AVFoundation

@MainActor
public final class SpeechRecognizer: ObservableObject {
    @Published public var transcript: String = ""
    @Published public var recentLines: [String] = []
    @Published public var isAuthorized: Bool = false
    @Published public var isRecognizing: Bool = false
    @Published public var isConnectedToBroadcast: Bool = false
    @Published public var audioPacketsReceived: Int = 0
    @Published public var currentLocale: Locale = Locale(identifier: "en-US")
    @Published public var statusMessage: String = "Ready"
    @Published public var isMicMode: Bool = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private var preferOfflineRecognition = true
    private var audioEngine: AVAudioEngine?

    public init() {
        updateLocale(currentLocale)
        requestPermissions()
    }

    public func updateLocale(_ locale: Locale) {
        currentLocale = locale
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    public func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isAuthorized = (status == .authorized)
                if status == .authorized {
                    self?.statusMessage = "Speech recognition authorized"
                } else {
                    self?.statusMessage = "Speech recognition permission: \(status)"
                }
            }
        }

        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                print("[SpeechRecognizer] Record permission granted: \(granted)")
            }
        }
    }

    public func startStreaming() {
        guard !isRecognizing else { return }
        stopStreaming()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[SpeechRecognizer] Recognizer is NOT available for locale \(currentLocale)")
            statusMessage = "Recognizer unavailable for \(currentLocale.identifier)"
            transcript = "Speech engine unavailable"
            return
        }

        print("[SpeechRecognizer] Starting stream with locale: \(recognizer.locale.identifier)")
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        if preferOfflineRecognition && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            statusMessage = "Using on-device speech engine"
        } else {
            request.requiresOnDeviceRecognition = false
            statusMessage = "Using Apple server speech engine"
        }

        self.recognitionRequest = request
        self.isRecognizing = true
        if transcript.isEmpty || transcript == "Speech engine unavailable" {
            self.transcript = "Listening for audio..."
        }

        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                self.transcript = text
                self.updateRecentLines(text)
            }

            if let error = error {
                print("[SpeechRecognizer] Recognition task error: \(error.localizedDescription)")
                // If on-device failed, fallback to network recognition
                if self.preferOfflineRecognition {
                    print("[SpeechRecognizer] Falling back to cloud recognition")
                    self.preferOfflineRecognition = false
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                self.restartStream()
            }
        }
    }

    public func appendPCMData(_ data: Data, asbd: AudioStreamBasicDescription) {
        audioPacketsReceived += 1

        if !isRecognizing {
            startStreaming()
        }

        guard isRecognizing, let request = recognitionRequest else { return }

        if let buffer = AudioPCMUtils.monoPCMBuffer(from: data, asbd: asbd) {
            request.append(buffer)
        }
    }

    private func updateRecentLines(_ text: String) {
        let words = text.split(separator: " ")
        if words.count > 16 {
            let tail = words.suffix(14).joined(separator: " ")
            self.transcript = tail
        }
    }

    public func stopStreaming() {
        isRecognizing = false
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func restartStream() {
        guard isRecognizing || isConnectedToBroadcast || isMicMode else { return }
        stopStreaming()
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.startStreaming()
        }
    }

    public func toggleMicMode() {
        if isMicMode {
            stopMicMode()
        } else {
            startMicMode()
        }
    }

    public func startMicMode() {
        stopMicMode()
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else { return }

        startStreaming()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.audioPacketsReceived += 1
                self.recognitionRequest?.append(buffer)
            }
        }

        do {
            try engine.start()
            self.audioEngine = engine
            self.isMicMode = true
            self.statusMessage = "Microphone mode active"
        } catch {
            print("[SpeechRecognizer] Failed to start audio engine: \(error)")
            self.statusMessage = "Mic error: \(error.localizedDescription)"
        }
    }

    public func stopMicMode() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isMicMode = false
        if !isConnectedToBroadcast {
            stopStreaming()
        }
    }

    public func clear() {
        transcript = ""
        recentLines.removeAll()
        audioPacketsReceived = 0
    }
}
