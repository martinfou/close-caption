//
//  AudioSocketServer.swift
//  LiveSub
//
import Foundation
import os.log

public protocol AudioSocketServerDelegate: AnyObject {
    func audioSocketServer(_ server: AudioSocketServer, didReceivePCMData data: Data)
    func audioSocketServerDidConnectClient(_ server: AudioSocketServer)
    func audioSocketServerDidDisconnectClient(_ server: AudioSocketServer)
}

public final class AudioSocketServer {
    public var delegate: AudioSocketServerDelegate?
    private let socketPath: String
    private var serverFD: Int32 = -1
    private var clientFD: Int32 = -1
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.livesub.socketServer", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.livesub.app", category: "AudioSocketServer")

    public init() {
        if let url = AudioSocketConstants.socketURL {
            self.socketPath = url.path
        } else {
            self.socketPath = "/tmp/livesub_fallback.sock"
        }
    }

    public func start() {
        queue.async { [weak self] in
            self?.setupAndListen()
        }
    }

    private func setupAndListen() {
        // Clean up previous socket file if present
        unlink(socketPath)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            logger.error("Failed to create UNIX domain socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = pathBytes.withUnsafeBufferPointer { buf in
                memcpy(ptr, buf.baseAddress, buf.count)
            }
        }

        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(serverFD, $0, len)
            }
        }

        guard bindResult == 0 else {
            logger.error("Failed to bind socket at path: \(self.socketPath)")
            stop()
            return
        }

        guard listen(serverFD, 5) == 0 else {
            logger.error("Failed to listen on socket")
            stop()
            return
        }

        isRunning = true
        logger.info("AudioSocketServer listening on \(self.socketPath)")

        while isRunning {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let fd = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(serverFD, $0, &clientLen)
                }
            }

            guard fd >= 0 else { continue }
            clientFD = fd
            logger.info("Broadcast extension connected!")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.audioSocketServerDidConnectClient(self)
            }

            readLoop(fd: fd)
        }
    }

    private func readLoop(fd: Int32) {
        while isRunning {
            // Read 4-byte payload size
            var payloadSizeBE: UInt32 = 0
            let headerBytes = Darwin.recv(fd, &payloadSizeBE, 4, MSG_WAITALL)
            guard headerBytes == 4 else { break }

            let payloadSize = Int(UInt32(bigEndian: payloadSizeBE))
            guard payloadSize > 0, payloadSize < 1_000_000 else { break }

            var buffer = Data(count: payloadSize)
            let bytesRead = buffer.withUnsafeMutableBytes { ptr in
                Darwin.recv(fd, ptr.baseAddress, payloadSize, MSG_WAITALL)
            }

            guard bytesRead == payloadSize else { break }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.audioSocketServer(self, didReceivePCMData: buffer)
            }
        }

        Darwin.close(fd)
        if clientFD == fd { clientFD = -1 }
        logger.info("Broadcast extension disconnected")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.audioSocketServerDidDisconnectClient(self)
        }
    }

    public func stop() {
        isRunning = false
        if clientFD >= 0 { Darwin.close(clientFD); clientFD = -1 }
        if serverFD >= 0 { Darwin.close(serverFD); serverFD = -1 }
        unlink(socketPath)
    }

    deinit {
        stop()
    }
}
