//
//  AudioSocketConstants.swift
//  LiveSub
//
import Foundation

public struct AudioSocketConstants {
    /// TCP localhost port for inter-process communication between LiveSub and LiveSubBroadcast
    public static let tcpPort: UInt16 = 19834
    
    // Default fallback sample rate
    public static let defaultSampleRate: Double = 44100.0
}
