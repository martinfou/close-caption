//
//  AudioPCMUtils.swift
//  LiveSub
//
import Foundation
import AVFoundation

public final class AudioPCMUtils {
    public static func monoPCMBuffer(from data: Data, asbd: AudioStreamBasicDescription) -> AVAudioPCMBuffer? {
        let sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 44100.0
        let channels = asbd.mChannelsPerFrame
        let bitsPerChannel = asbd.mBitsPerChannel

        guard channels > 0 else { return nil }

        if bitsPerChannel == 16 {
            // 16-bit Linear PCM
            guard let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            ) else { return nil }

            let bytesPerFrame = Int(channels * 2)
            guard bytesPerFrame > 0 else { return nil }
            let frameCount = data.count / bytesPerFrame
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: UInt32(frameCount)) else {
                return nil
            }
            buffer.frameLength = UInt32(frameCount)

            guard let channelData = buffer.int16ChannelData?[0] else { return nil }

            data.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                let int16Ptr = baseAddress.assumingMemoryBound(to: Int16.self)

                if channels == 1 {
                    memcpy(channelData, int16Ptr, frameCount * MemoryLayout<Int16>.size)
                } else if channels == 2 {
                    // Downmix stereo to mono
                    for frame in 0..<frameCount {
                        let left = Int32(int16Ptr[frame * 2])
                        let right = Int32(int16Ptr[frame * 2 + 1])
                        channelData[frame] = Int16(clamping: (left + right) / 2)
                    }
                } else {
                    // Multi-channel: take first channel or average
                    for frame in 0..<frameCount {
                        channelData[frame] = int16Ptr[frame * Int(channels)]
                    }
                }
            }
            return buffer

        } else if bitsPerChannel == 32 {
            // 32-bit Float Linear PCM
            guard let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            ) else { return nil }

            let bytesPerFrame = Int(channels * 4)
            guard bytesPerFrame > 0 else { return nil }
            let frameCount = data.count / bytesPerFrame
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: UInt32(frameCount)) else {
                return nil
            }
            buffer.frameLength = UInt32(frameCount)

            guard let channelData = buffer.floatChannelData?[0] else { return nil }

            data.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                let floatPtr = baseAddress.assumingMemoryBound(to: Float32.self)

                if channels == 1 {
                    memcpy(channelData, floatPtr, frameCount * MemoryLayout<Float32>.size)
                } else if channels == 2 {
                    // Downmix stereo to mono
                    for frame in 0..<frameCount {
                        let left = floatPtr[frame * 2]
                        let right = floatPtr[frame * 2 + 1]
                        channelData[frame] = (left + right) * 0.5
                    }
                } else {
                    for frame in 0..<frameCount {
                        channelData[frame] = floatPtr[frame * Int(channels)]
                    }
                }
            }
            return buffer
        }

        return nil
    }
}
