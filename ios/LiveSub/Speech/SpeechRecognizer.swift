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
    @Published public var currentLocale: Locale = Locale(identifier: "es-ES")
    @Published public var statusMessage: String = "Ready"
    @Published public var isMicMode: Bool = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private var preferOfflineRecognition = true
    private var audioEngine: AVAudioEngine?
    private var shouldKeepRecognizing = false

    public init() {
        updateLocale(currentLocale)
        requestPermissions()
    }

    public func updateLocale(_ locale: Locale) {
        currentLocale = locale
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        if isRecognizing {
            restartStream()
        }
    }

    public func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isAuthorized = (status == .authorized)
                if status == .authorized {
                    self?.statusMessage = "Speech engine ready"
                } else {
                    self?.statusMessage = "Speech auth needed"
                }
            }
        }

        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }

    public func startStreaming() {
        guard !isRecognizing else { return }
        stopStreaming()

        shouldKeepRecognizing = true

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
            statusMessage = "Using on-device engine (\(recognizer.locale.identifier))"
        } else {
            request.requiresOnDeviceRecognition = false
            statusMessage = "Using speech engine (\(recognizer.locale.identifier))"
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
                // Feed transcription directly to TranslationManager
                TranslationManager.shared.translate(sourceText: text)
            }

            if let error = error {
                print("[SpeechRecognizer] Recognition task error: \(error.localizedDescription)")
                if self.preferOfflineRecognition {
                    self.preferOfflineRecognition = false
                }
            }

            // Only restart if we still intend to be streaming
            if (error != nil || (result?.isFinal ?? false)) && self.shouldKeepRecognizing {
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
        shouldKeepRecognizing = false
        isRecognizing = false
        restartTimer?.invalidate()
        restartTimer = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func restartStream() {
        guard shouldKeepRecognizing else { return }
        stopStreaming()
        shouldKeepRecognizing = true
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.startStreaming()
            }
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

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("[SpeechRecognizer] Failed to configure audio session for mic: \(error)")
        }

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
        isMicMode = false

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.audioEngine = nil
        }

        // Restore playback-only audio session to immediately dismiss iOS orange mic indicator
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[SpeechRecognizer] Failed to restore playback session: \(error)")
        }

        stopStreaming()
        self.statusMessage = "Microphone mode stopped (Ready)"
    }

    public func clear() {
        transcript = ""
        recentLines.removeAll()
        audioPacketsReceived = 0
        TranslationManager.shared.translatedText = ""
    }
}
