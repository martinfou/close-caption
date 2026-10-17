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
    @Published public var currentLocale: Locale = Locale(identifier: "en-US")

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var restartTimer: Timer?

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
            }
        }
    }

    public func startStreaming() {
        guard !isRecognizing else { return }
        stopStreaming()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[SpeechRecognizer] Recognizer is NOT available for locale \(currentLocale)")
            transcript = "Speech engine unavailable"
            return
        }

        print("[SpeechRecognizer] Starting stream with recognizer: \(recognizer.locale.identifier)")
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        // Enables offline neural engine transcription (zero network lag)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            print("[SpeechRecognizer] On-device recognition enabled")
        } else {
            print("[SpeechRecognizer] Using standard recognition (on-device not supported on this device/simulator)")
        }

        self.recognitionRequest = request
        self.isRecognizing = true
        self.transcript = "Listening for audio..."

        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                print("[SpeechRecognizer] Recognized text: \(text)")
                self.transcript = text
                self.updateRecentLines(text)
            }

            if let error = error {
                print("[SpeechRecognizer] Recognition task error: \(error.localizedDescription)")
            }

            if error != nil || (result?.isFinal ?? false) {
                self.restartStream()
            }
        }
    }

    public func appendPCMData(_ data: Data) {
        guard isRecognizing, let request = recognitionRequest else {
            print("[SpeechRecognizer] appendPCMData skipped (isRecognizing: \(isRecognizing), request: \(recognitionRequest != nil))")
            return
        }
        if let buffer = AudioPCMUtils.pcmBuffer(from: data) {
            request.append(buffer)
        }
    }

    private func updateRecentLines(_ text: String) {
        let words = text.split(separator: " ")
        if words.count > 16 {
            // Keep the last ~14 words for the floating subtitle HUD
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
        stopStreaming()
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.startStreaming()
        }
    }

    public func clear() {
        transcript = ""
        recentLines.removeAll()
    }
}
