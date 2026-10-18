//
//  BroadcastPickerRepresentable.swift
//  LiveSub
//
import SwiftUI
import ReplayKit

/// Hosts the system broadcast picker invisibly so any SwiftUI button can open it
/// by incrementing `trigger`.
public struct BroadcastPickerRepresentable: UIViewRepresentable {
    @Binding var trigger: Int

    public init(trigger: Binding<Int>) {
        self._trigger = trigger
    }

    public final class Coordinator {
        var lastTrigger = 0
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = "com.martinfournier.livesub.LiveSubBroadcast"
        picker.showsMicrophoneButton = false
        picker.alpha = 0.02
        return picker
    }

    public func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        guard context.coordinator.lastTrigger != trigger else { return }
        context.coordinator.lastTrigger = trigger
        for subview in uiView.subviews {
            if let button = subview as? UIButton {
                button.sendActions(for: .allTouchEvents)
            }
        }
    }
}
