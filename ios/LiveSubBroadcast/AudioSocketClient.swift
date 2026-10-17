//
//  AudioSocketClient.swift
//  LiveSubBroadcast
//
import Foundation
import CoreMedia

public final class AudioSocketClient {
    private var socketFD: Int32 = -1
    private let socketPath: String

    public init() {
        if let url = AudioSocketConstants.socketURL {
            self.socketPath = url.path
        } else {
            self.socketPath = "/tmp/livesub_fallback.sock"
        }
    }

    public func connect() -> Bool {
        disconnect()
        socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }

        // Make socket non-blocking or short timeout so it doesn't freeze the extension
        var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = pathBytes.withUnsafeBufferPointer { buf in
                memcpy(ptr, buf.baseAddress, buf.count)
            }
        }

        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
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
        guard socketFD >= 0,
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

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

        // Send 4-byte header length + raw PCM payload
        var payloadLength = UInt32(totalLengthOut).bigEndian
        _ = Darwin.send(socketFD, &payloadLength, 4, 0)
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
