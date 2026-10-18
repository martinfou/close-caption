//
//  AudioSocketClient.swift
//  LiveSubBroadcast
//
import Foundation
import CoreMedia

public final class AudioSocketClient {
    private var socketFD: Int32 = -1

    public init() {}

    public func connect() -> Bool {
        disconnect()

        socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }

        var opt: Int32 = 1
        #if canImport(Darwin)
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))
        #endif

        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
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

    public func send(sampleBuffer: CMSampleBuffer) {
        guard socketFD >= 0 else { return }

        // Extract AudioStreamBasicDescription from the sample buffer
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            return
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var lengthAtOffsetOut: Int = 0
        var totalLengthOut: Int = 0
        var dataPointerOut: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffsetOut,
            totalLengthOut: &totalLengthOut,
            dataPointerOut: &dataPointerOut
        )

        guard status == kCMBlockBufferNoErr, let data = dataPointerOut, totalLengthOut > 0 else { return }

        let asbdSize = MemoryLayout<AudioStreamBasicDescription>.size
        let totalPayloadSize = asbdSize + totalLengthOut

        // 4-byte header length
        var payloadLengthBE = UInt32(totalPayloadSize).bigEndian

        // Prepare ASBD bytes
        var asbdCopy = asbd

        // Send length header, ASBD, and PCM payload
        withUnsafePointer(to: &payloadLengthBE) { lenPtr in
            _ = Darwin.send(socketFD, lenPtr, 4, 0)
        }
        withUnsafePointer(to: &asbdCopy) { asbdPtr in
            _ = Darwin.send(socketFD, asbdPtr, asbdSize, 0)
        }
        _ = Darwin.send(socketFD, data, totalLengthOut, 0)
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
