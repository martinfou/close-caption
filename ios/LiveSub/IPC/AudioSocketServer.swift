//
//  AudioSocketServer.swift
//  LiveSub
//
import Foundation
import os.log
import CoreMedia

public protocol AudioSocketServerDelegate: AnyObject {
    func audioSocketServer(_ server: AudioSocketServer, didReceivePCMData data: Data, asbd: AudioStreamBasicDescription)
    func audioSocketServer(_ server: AudioSocketServer, didReceiveDebug text: String)
    func audioSocketServerDidConnectClient(_ server: AudioSocketServer)
    func audioSocketServerDidDisconnectClient(_ server: AudioSocketServer)
}

public final class AudioSocketServer {
    public weak var delegate: AudioSocketServerDelegate?
    private var serverFD: Int32 = -1
    private var clientFD: Int32 = -1
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.livesub.tcpServer", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.livesub.app", category: "AudioSocketServer")

    public init() {}

    public func start() {
        queue.async { [weak self] in
            self?.setupAndListen()
        }
    }

    private func setupAndListen() {
        stop()

        serverFD = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            logger.error("Failed to create TCP socket")
            return
        }

        var opt: Int32 = 1
        setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        #if canImport(Darwin)
        setsockopt(serverFD, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))
        #endif

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = AudioSocketConstants.tcpPort.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(serverFD, $0, len)
            }
        }

        guard bindResult == 0 else {
            logger.error("Failed to bind TCP socket on port \(AudioSocketConstants.tcpPort)")
            stop()
            return
        }

        guard Darwin.listen(serverFD, 5) == 0 else {
            logger.error("Failed to listen on TCP socket")
            stop()
            return
        }

        isRunning = true
        logger.info("AudioSocketServer listening on 127.0.0.1:\(AudioSocketConstants.tcpPort)")

        while isRunning {
            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let fd = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(serverFD, $0, &clientLen)
                }
            }

            guard fd >= 0 else { continue }
            clientFD = fd
            var optVal: Int32 = 1
            #if canImport(Darwin)
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &optVal, socklen_t(MemoryLayout<Int32>.size))
            #endif

            logger.info("Broadcast extension connected via TCP loopback!")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.audioSocketServerDidConnectClient(self)
            }

            readLoop(fd: fd)
        }
    }

    private func readLoop(fd: Int32) {
        let asbdSize = MemoryLayout<AudioStreamBasicDescription>.size

        while isRunning {
            // Read 4-byte payload size
            var payloadSizeBE: UInt32 = 0
            let headerBytes = Darwin.recv(fd, &payloadSizeBE, 4, MSG_WAITALL)
            guard headerBytes == 4 else { break }

            let totalPayloadSize = Int(UInt32(bigEndian: payloadSizeBE))
            guard totalPayloadSize > asbdSize, totalPayloadSize < 1_000_000 else { break }

            // Read ASBD
            var asbd = AudioStreamBasicDescription()
            let asbdBytes = Darwin.recv(fd, &asbd, asbdSize, MSG_WAITALL)
            guard asbdBytes == asbdSize else { break }

            // Read raw PCM data
            let audioDataSize = totalPayloadSize - asbdSize
            var buffer = Data(count: audioDataSize)
            let bytesRead = buffer.withUnsafeMutableBytes { ptr in
                Darwin.recv(fd, ptr.baseAddress, audioDataSize, MSG_WAITALL)
            }

            guard bytesRead == audioDataSize else { break }

            if asbd.mSampleRate < 0 {
                let text = String(data: buffer, encoding: .utf8) ?? "?"
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.audioSocketServer(self, didReceiveDebug: text)
                }
                continue
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.audioSocketServer(self, didReceivePCMData: buffer, asbd: asbd)
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
    }

    deinit {
        stop()
    }
}
