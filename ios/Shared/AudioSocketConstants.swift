//
//  AudioSocketConstants.swift
//  LiveSub
//
import Foundation

public struct AudioSocketConstants {
    public static let appGroupId = "group.com.martinfournier.livesub"
    public static let socketFileName = "audio_stream.sock"
    
    public static var socketURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(socketFileName)
    }
    
    // Default ReplayKit audio is 44.1kHz or 48kHz 16-bit Linear PCM, 1 or 2 channels
    public static let sampleRate: Double = 44100.0
    public static let channelCount: UInt32 = 1
}
