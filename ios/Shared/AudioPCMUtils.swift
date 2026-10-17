//
//  AudioPCMUtils.swift
//  LiveSub
//
import Foundation
import AVFoundation

public final class AudioPCMUtils {
    public static let sharedFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 44100.0,
        channels: 1,
        interleaved: true
    )!

    public static func pcmBuffer(from data: Data, format: AVAudioFormat = sharedFormat) -> AVAudioPCMBuffer? {
        let frameCapacity = UInt32(data.count) / (format.streamDescription.pointee.mBytesPerFrame)
        guard frameCapacity > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }
        buffer.frameLength = frameCapacity
        data.withUnsafeBytes { rawBufferPointer in
            if let address = rawBufferPointer.baseAddress {
                memcpy(buffer.int16ChannelData?[0], address, data.count)
            }
        }
        return buffer
    }
}
