//
//  AudioSocketClient.swift
//  LiveSubBroadcast
//
import Foundation
import CoreMedia
import AVFoundation

public final class AudioSocketClient {
    private var socketFD: Int32 = -1

    public init() {}

    public func connect() -> Bool {
        disconnect()

        socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }

        var opt: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = AudioSocketConstants.tcpPort.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketFD, $0, len)
            }
        }

        if result < 0 {
            disconnect()
            return false
        }
        return true
    }

    /// Returns false if the connection is broken and the caller should reconnect.
    @discardableResult
    public func send(sampleBuffer: CMSampleBuffer) -> Bool {
        guard socketFD >= 0 else { return false }

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return true
        }
        var srcASBD = asbdPtr.pointee
        guard let srcFormat = AVAudioFormat(streamDescription: &srcASBD) else { return true }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frames) else { return true }
        pcm.frameLength = frames

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList
        )
        guard status == noErr else { return true }

        // Downmix whatever ReplayKit gave us (int16/float32, interleaved or not) to mono Int16.
        let channels = Int(srcFormat.channelCount)
        let stride = pcm.stride
        var mono = [Int16](repeating: 0, count: Int(frames))

        if let f = pcm.floatChannelData {
            for i in 0..<Int(frames) {
                var sum: Float = 0
                for c in 0..<channels { sum += f[c][i * stride] }
                let v = max(-1.0, min(1.0, sum / Float(channels)))
                mono[i] = Int16(v * 32767.0)
            }
        } else if let s = pcm.int16ChannelData {
            for i in 0..<Int(frames) {
                var sum: Int32 = 0
                for c in 0..<channels { sum += Int32(s[c][i * stride]) }
                mono[i] = Int16(clamping: sum / Int32(channels))
            }
        } else {
            return true
        }

        var outASBD = AudioStreamBasicDescription(
            mSampleRate: srcASBD.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        let asbdSize = MemoryLayout<AudioStreamBasicDescription>.size
        let audioBytes = mono.count * MemoryLayout<Int16>.size

        var packet = Data()
        var lengthBE = UInt32(asbdSize + audioBytes).bigEndian
        packet.append(Data(bytes: &lengthBE, count: 4))
        packet.append(Data(bytes: &outASBD, count: asbdSize))
        mono.withUnsafeBytes { packet.append(contentsOf: $0) }

        return sendAll(packet)
    }

    private func sendAll(_ data: Data) -> Bool {
        var offset = 0
        let total = data.count
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return false }
            while offset < total {
                let n = Darwin.send(socketFD, base + offset, total - offset, 0)
                if n <= 0 {
                    disconnect()
                    return false
                }
                offset += n
            }
            return true
        }
    }

    public func disconnect() {
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
    }

    deinit {
        disconnect()
    }
}
