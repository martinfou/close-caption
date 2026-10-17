//
//  SubtitleOverlayView.swift
//  LiveSub
//
import SwiftUI

public struct SubtitleOverlayView: View {
    @ObservedObject public var speechRecognizer: SpeechRecognizer
    @AppStorage("fontSize") private var fontSize: Double = 16.0
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.82

    public init(speechRecognizer: SpeechRecognizer) {
        self.speechRecognizer = speechRecognizer
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(backgroundOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 5)

            HStack(alignment: .top, spacing: 10) {
                // Live Indicator Dot
                Circle()
                    .fill(speechRecognizer.isRecognizing ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(speechRecognizer.transcript.isEmpty ? "LiveSub active..." : speechRecognizer.transcript)
                        .font(.system(size: CGFloat(fontSize), weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: speechRecognizer.transcript)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}
