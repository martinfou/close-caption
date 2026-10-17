//
//  SampleHandler.swift
//  LiveSubBroadcast
//
import ReplayKit
import os.log

public final class SampleHandler: RPBroadcastSampleHandler {
    private let client = AudioSocketClient()
    private let logger = Logger(subsystem: "com.livesub.broadcast", category: "SampleHandler")
    private var isConnected = false

    public override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        logger.info("LiveSub ReplayKit broadcast started")
        isConnected = client.connect()
        if !isConnected {
            logger.warning("Could not connect to Main App socket immediately; will retry on first buffer.")
        }
    }

    public override func broadcastPaused() {
        logger.info("Broadcast paused")
    }

    public override func broadcastResumed() {
        logger.info("Broadcast resumed")
        if !isConnected {
            isConnected = client.connect()
        }
    }

    public override func broadcastFinished() {
        logger.info("LiveSub ReplayKit broadcast finished")
        client.disconnect()
        isConnected = false
    }

    public override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .audioApp:
            // This is internal media/game/system audio from other apps
            if !isConnected {
                isConnected = client.connect()
            }
            if isConnected {
                client.send(sampleBuffer: sampleBuffer)
            }
        case .audioMic:
            // Optionally capture ambient microphone if the user toggled it
            break
        case .video:
            // Ignored to stay well under the 50MB Jetsam memory ceiling
            break
        @unknown default:
            break
        }
    }
}
