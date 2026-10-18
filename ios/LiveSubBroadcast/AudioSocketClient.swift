//
//  AudioSocketClient.swift
//  LiveSubBroadcast
//
import Foundation
import CoreMedia
import AVFoundation

public final class AudioSocketClient {
    private var socketFD: Int32 = -1
    private var lastDebugTime = Date.distantPast
    private var peak: Float = 0
    private var sentBuffers = 0
    private var lastFailure = ""

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
        sendDebug("extension connected")
        return true
    }

    /// Returns false if the connection is broken and the caller should reconnect.
    @discardableResult
    public func send(sampleBuffer: CMSampleBuffer) -> Bool {
        guard socketFD >= 0 else { return false }

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            lastFailure = "no format description"
            return maybeDebug()
        }
        var srcASBD = asbdPtr.pointee

        guard let mono = monoInt16(from: sampleBuffer, asbd: &srcASBD) else {
            return maybeDebug(srcASBD)
        }

        for s in mono { peak = max(peak, abs(Float(s)) / 32768.0) }
        sentBuffers += 1

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

        let ok = sendPacket(asbd: &outASBD, payload: mono.withUnsafeBytes { Data($0) })
        if !ok { return false }
        return maybeDebug(srcASBD)
    }

    // MARK: - Conversion

    private func monoInt16(from sampleBuffer: CMSampleBuffer, asbd: inout AudioStreamBasicDescription) -> [Int16]? {
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else { lastFailure = "0 frames"; return nil }
        let channels = max(1, Int(asbd.mChannelsPerFrame))

        // Preferred: let CoreMedia copy into an AVAudioPCMBuffer (handles interleaved/planar/float/int).
        if let format = AVAudioFormat(streamDescription: &asbd),
           let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) {
            pcm.frameLength = AVAudioFrameCount(frames)
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
                sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList
            )
            if status == noErr {
                let stride = pcm.stride
                var mono = [Int16](repeating: 0, count: frames)
                if let f = pcm.floatChannelData {
                    for i in 0..<frames {
                        var sum: Float = 0
                        for c in 0..<channels { sum += f[c][i * stride] }
                        mono[i] = Int16(max(-1, min(1, sum / Float(channels))) * 32767)
                    }
                    return mono
                } else if let s = pcm.int16ChannelData {
                    for i in 0..<frames {
                        var sum: Int32 = 0
                        for c in 0..<channels { sum += Int32(s[c][i * stride]) }
                        mono[i] = Int16(clamping: sum / Int32(channels))
                    }
                    return mono
                } else {
                    lastFailure = "unsupported sample type"
                }
            } else {
                lastFailure = "CopyPCMData status \(status)"
            }
        } else {
            lastFailure = "AVAudioFormat init failed"
        }

        // Fallback: raw interleaved bytes straight from the block buffer.
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var ptr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length, dataPointerOut: &ptr) == kCMBlockBufferNoErr,
              let base = ptr else { return nil }
        var mono = [Int16](repeating: 0, count: frames)
        if asbd.mBitsPerChannel == 16 {
            let p = UnsafeRawPointer(base).assumingMemoryBound(to: Int16.self)
            let n = min(frames, length / (2 * channels))
            for i in 0..<n {
                var sum: Int32 = 0
                for c in 0..<channels { sum += Int32(p[i * channels + c]) }
                mono[i] = Int16(clamping: sum / Int32(channels))
            }
            return mono
        } else if asbd.mBitsPerChannel == 32 {
            let p = UnsafeRawPointer(base).assumingMemoryBound(to: Float32.self)
            let n = min(frames, length / (4 * channels))
            for i in 0..<n {
                var sum: Float = 0
                for c in 0..<channels { sum += p[i * channels + c] }
                mono[i] = Int16(max(-1, min(1, sum / Float(channels))) * 32767)
            }
            return mono
        }
        return nil
    }

    // MARK: - Diagnostics

    /// Every ~2s tells the app what the extension is seeing (format, loudness, failures).
    private func maybeDebug(_ asbd: AudioStreamBasicDescription? = nil) -> Bool {
        guard Date().timeIntervalSince(lastDebugTime) > 2 else { return true }
        lastDebugTime = Date()
        var text = "ext sent \(sentBuffers) bufs, peak \(String(format: "%.2f", peak))"
        if let a = asbd {
            text += ", \(Int(a.mSampleRate))Hz ch\(a.mChannelsPerFrame) \(a.mBitsPerChannel)bit flags \(a.mFormatFlags)"
        }
        if !lastFailure.isEmpty { text += ", note: \(lastFailure)" }
        peak = 0
        return sendDebug(text)
    }

    @discardableResult
    private func sendDebug(_ text: String) -> Bool {
        var marker = AudioStreamBasicDescription()
        marker.mSampleRate = -1
        return sendPacket(asbd: &marker, payload: Data(text.utf8))
    }

    // MARK: - Transport

    private func sendPacket(asbd: inout AudioStreamBasicDescription, payload: Data) -> Bool {
        let asbdSize = MemoryLayout<AudioStreamBasicDescription>.size
        var packet = Data()
        var lengthBE = UInt32(asbdSize + payload.count).bigEndian
        packet.append(Data(bytes: &lengthBE, count: 4))
        packet.append(Data(bytes: &asbd, count: asbdSize))
        packet.append(payload)
        return sendAll(packet)
    }

    private func sendAll(_ data: Data) -> Bool {
        guard socketFD >= 0 else { return false }
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
