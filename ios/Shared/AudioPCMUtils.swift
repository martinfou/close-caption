//
//  AudioPCMUtils.swift
//  LiveSub
//
import Foundation
import AVFoundation

public final class AudioPCMUtils {
    /// Converts mono/stereo interleaved 16-bit or 32-bit float PCM bytes into a mono
    /// Float32 buffer, which is the format SFSpeechRecognizer handles most reliably.
    public static func monoPCMBuffer(from data: Data, asbd: AudioStreamBasicDescription) -> AVAudioPCMBuffer? {
        let sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 44100.0
        let channels = Int(asbd.mChannelsPerFrame)
        let bits = asbd.mBitsPerChannel
        guard channels > 0, bits == 16 || bits == 32 else { return nil }

        let bytesPerSample = Int(bits / 8)
        let frameCount = data.count / (bytesPerSample * channels)
        guard frameCount > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            if bits == 16 {
                let p = base.assumingMemoryBound(to: Int16.self)
                for i in 0..<frameCount {
                    var sum: Float = 0
                    for c in 0..<channels { sum += Float(p[i * channels + c]) / 32768.0 }
                    out[i] = sum / Float(channels)
                }
            } else {
                let p = base.assumingMemoryBound(to: Float32.self)
                for i in 0..<frameCount {
                    var sum: Float = 0
                    for c in 0..<channels { sum += p[i * channels + c] }
                    out[i] = sum / Float(channels)
                }
            }
        }
        return buffer
    }
}
