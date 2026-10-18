//
//  BackgroundKeepAlive.swift
//  LiveSub
//
//  iOS suspends background apps that are not actively playing/recording audio.
//  While suspended, the loopback socket server stops accepting data from the
//  ReplayKit broadcast extension. Playing inaudible silence (mixed with other
//  audio, so YouTube is never interrupted) keeps the app running.
//
import Foundation
import AVFoundation
import UIKit

public final class BackgroundKeepAlive {
    public static let shared = BackgroundKeepAlive()

    private var player: AVAudioPlayer?
    private var observersInstalled = false

    private init() {}

    public func start() {
        configureSession()
        installObservers()

        if player == nil {
            player = try? AVAudioPlayer(data: Self.silentWAV())
            player?.numberOfLoops = -1
            player?.volume = 0.0
            player?.prepareToPlay()
        }
        if player?.isPlaying != true {
            player?.play()
        }
    }

    /// Call after anything changes the audio session category (e.g. leaving mic mode).
    public func ensureRunning() {
        start()
    }

    private func configureSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[KeepAlive] Session error: \(error)")
        }
    }

    private func installObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self?.start()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.start()
        }
    }

    /// One second of 16-bit mono 8 kHz silence as an in-memory WAV file.
    private static func silentWAV() -> Data {
        let sampleRate: UInt32 = 8000
        let dataSize = UInt32(sampleRate * 2)
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(36 + dataSize)
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16)
        u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(dataSize)
        d.append(Data(count: Int(dataSize)))
        return d
    }
}
