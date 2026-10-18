//
//  PiPManager.swift
//  LiveSub
//
import AVKit
import SwiftUI
import Combine

public final class PiPManager: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    public static let shared = PiPManager()

    @Published public var isPiPActive = false
    @Published public var isPiPSupported = false

    public let sourceView = UIView()
    private var pipController: AVPictureInPictureController?
    private var pipViewController: AVPictureInPictureVideoCallViewController?
    private var hostingController: UIHostingController<SubtitleOverlayView>?

    public func configure(with speechRecognizer: SpeechRecognizer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isPiPSupported = false
            return
        }
        isPiPSupported = true

        let overlay = SubtitleOverlayView(speechRecognizer: speechRecognizer)
        let host = UIHostingController(rootView: overlay)
        host.view.backgroundColor = .clear
        self.hostingController = host

        let callVC = AVPictureInPictureVideoCallViewController()
        callVC.preferredContentSize = CGSize(width: 360, height: 90)
        callVC.view.backgroundColor = .clear
        callVC.view.addSubview(host.view)

        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: callVC.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: callVC.view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: callVC.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: callVC.view.trailingAnchor)
        ])

        self.pipViewController = callVC

        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: callVC
        )

        pipController = AVPictureInPictureController(contentSource: contentSource)
        pipController?.delegate = self
        pipController?.canStartPictureInPictureAutomaticallyFromInline = true
    }

    public func togglePiP() {
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    // MARK: - AVPictureInPictureControllerDelegate
    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isPiPActive = true }
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isPiPActive = false }
    }
}

public struct PiPSourceViewRepresentable: UIViewRepresentable {
    let view: UIView

    public init(view: UIView) {
        self.view = view
    }

    public func makeUIView(context: Context) -> UIView {
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {}
}
