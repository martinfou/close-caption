//
//  LiveSubApp.swift
//  LiveSub
//
import SwiftUI
import AVFoundation

@main
struct LiveSubApp: App {
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var coordinator: SocketCoordinator?
    private let socketServer = AudioSocketServer()

    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(speechRecognizer)
                .onAppear {
                    setupIPC()
                    PiPManager.shared.configure(with: speechRecognizer)
                }
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .mixWithOthers ensures LiveSub does NOT pause Spotify/YouTube playback!
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            print("Failed to configure background playback audio session: \(error)")
        }
    }

    private func setupIPC() {
        let coord = SocketCoordinator(speechRecognizer: speechRecognizer)
        self.coordinator = coord
        socketServer.delegate = coord
        socketServer.start()
        print("[LiveSubApp] IPC SocketServer started and coordinator retained.")
    }
}

final class SocketCoordinator: AudioSocketServerDelegate {
    private let speechRecognizer: SpeechRecognizer

    init(speechRecognizer: SpeechRecognizer) {
        self.speechRecognizer = speechRecognizer
    }

    func audioSocketServer(_ server: AudioSocketServer, didReceivePCMData data: Data) {
        Task { @MainActor in
            speechRecognizer.appendPCMData(data)
        }
    }

    func audioSocketServerDidConnectClient(_ server: AudioSocketServer) {
        Task { @MainActor in
            speechRecognizer.startStreaming()
        }
    }

    func audioSocketServerDidDisconnectClient(_ server: AudioSocketServer) {
        Task { @MainActor in
            speechRecognizer.stopStreaming()
        }
    }
}
