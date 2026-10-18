//
//  BroadcastPickerRepresentable.swift
//  LiveSub
//
import SwiftUI
import ReplayKit

public struct BroadcastPickerRepresentable: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
        picker.preferredExtension = "com.martinfournier.livesub.LiveSubBroadcast"
        picker.showsMicrophoneButton = false
        picker.tintColor = .white
        return picker
    }

    public func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
