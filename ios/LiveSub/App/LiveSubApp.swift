//
//  LiveSubApp.swift
//  LiveSub
//
import SwiftUI
import AVFoundation
import CoreMedia

@main
struct LiveSubApp: App {
    @StateObject private var speechRecognizer = SpeechRecognizer()

    init() {
        // Keeps the app (and the broadcast socket server) running while the user
        // is in YouTube/Safari/etc. Mixes with other audio, so nothing is interrupted.
        BackgroundKeepAlive.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(speechRecognizer)
                .onAppear {
                    IPCController.shared.startIfNeeded(speechRecognizer: speechRecognizer)
                    PiPManager.shared.configure(with: speechRecognizer)
                }
        }
    }
}

/// Owns the loopback socket server for the whole process lifetime (started exactly once).
final class IPCController {
    static let shared = IPCController()

    private let socketServer = AudioSocketServer()
    private var coordinator: SocketCoordinator?
    private var started = false

    @MainActor
    func startIfNeeded(speechRecognizer: SpeechRecognizer) {
        guard !started else { return }
        started = true
        let coord = SocketCoordinator(speechRecognizer: speechRecognizer)
        coordinator = coord
        socketServer.delegate = coord
        socketServer.start()
        print("[LiveSubApp] IPC TCP SocketServer started on localhost.")
    }
}

final class SocketCoordinator: AudioSocketServerDelegate {
    private let speechRecognizer: SpeechRecognizer

    init(speechRecognizer: SpeechRecognizer) {
        self.speechRecognizer = speechRecognizer
    }

    func audioSocketServer(_ server: AudioSocketServer, didReceivePCMData data: Data, asbd: AudioStreamBasicDescription) {
        Task { @MainActor in
            speechRecognizer.appendPCMData(data, asbd: asbd)
        }
    }

    func audioSocketServer(_ server: AudioSocketServer, didReceiveDebug text: String) {
        Task { @MainActor in
            speechRecognizer.debugInfo = text
        }
    }

    func audioSocketServerDidConnectClient(_ server: AudioSocketServer) {
        Task { @MainActor in
            speechRecognizer.isConnectedToBroadcast = true
            speechRecognizer.statusMessage = "Broadcast connected"
            speechRecognizer.startStreaming()
        }
    }

    func audioSocketServerDidDisconnectClient(_ server: AudioSocketServer) {
        Task { @MainActor in
            speechRecognizer.isConnectedToBroadcast = false
            speechRecognizer.statusMessage = "Broadcast ended"
            if !speechRecognizer.isMicMode {
                speechRecognizer.stopStreaming()
            }
        }
    }
}
