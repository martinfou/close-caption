//
//  SubtitleOverlayView.swift
//  LiveSub
//
import SwiftUI

public struct SubtitleOverlayView: View {
    @ObservedObject public var speechRecognizer: SpeechRecognizer
    @ObservedObject private var translationManager = TranslationManager.shared
    @AppStorage("fontSize") private var fontSize: Double = 16.0
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.85

    public init(speechRecognizer: SpeechRecognizer) {
        self.speechRecognizer = speechRecognizer
    }

    private var primaryText: String {
        if translationManager.isTranslationEnabled && !translationManager.translatedText.isEmpty {
            return translationManager.translatedText
        }
        return speechRecognizer.transcript.isEmpty
            ? (speechRecognizer.debugInfo.isEmpty ? "Listening… (\(speechRecognizer.audioPacketsReceived) buffers)" : "\(speechRecognizer.debugInfo) • \(speechRecognizer.audioPacketsReceived) bufs")
            : speechRecognizer.transcript
    }

    private var showOriginalText: Bool {
        translationManager.isTranslationEnabled &&
        translationManager.showOriginalInPiP &&
        !translationManager.translatedText.isEmpty &&
        !speechRecognizer.transcript.isEmpty &&
        translationManager.sourceLanguage.langCode != translationManager.targetLanguage.langCode
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
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)

            HStack(alignment: .top, spacing: 10) {
                // Live Indicator Dot
                Circle()
                    .fill(speechRecognizer.isRecognizing ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 3) {
                    // Header language tag
                    if translationManager.isTranslationEnabled {
                        HStack(spacing: 4) {
                            Text("\(translationManager.sourceLanguage.flag) \(translationManager.sourceLanguage.langCode.uppercased())")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.cyan)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.gray)
                            Text("\(translationManager.targetLanguage.flag) \(translationManager.targetLanguage.langCode.uppercased())")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                        }
                    }

                    // Primary Translated Subtitle
                    Text(primaryText)
                        .font(.system(size: CGFloat(fontSize), weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: primaryText)

                    // Secondary Original Text (Optional)
                    if showOriginalText {
                        Text(speechRecognizer.transcript)
                            .font(.system(size: CGFloat(max(10, fontSize - 4)), weight: .medium, design: .rounded))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}
