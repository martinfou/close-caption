//
//  ContentView.swift
//  LiveSub
//
import SwiftUI

#if canImport(Translation)
import Translation
#endif

public struct ContentView: View {
    @EnvironmentObject var speechRecognizer: SpeechRecognizer
    @ObservedObject var pipManager = PiPManager.shared
    @ObservedObject var translationManager = TranslationManager.shared
    @AppStorage("fontSize") private var fontSize: Double = 16.0

    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.12).ignoresSafeArea()

                // Hidden view required by iOS to attach PiP source view to the window
                PiPSourceViewRepresentable(view: pipManager.sourceView)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)

                ScrollView {
                    VStack(spacing: 18) {
                        // Audio Broadcast & Mic Status Card
                        statusCard

                        // Dedicated Language A ➔ Language B Translation Card
                        translationControlCard

                        // Subtitle Live Box (Shows Translated + Original)
                        captionPreviewBox

                        // Action Controls (PiP & Mic)
                        controlsGrid

                        // Settings & Customization
                        settingsSection

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
            }
            .navigationTitle("LiveSub")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(TranslationTaskModifier())
            .onChange(of: speechRecognizer.transcript) { newText in
                translationManager.translate(sourceText: newText)
            }
            .onChange(of: translationManager.targetLanguage) { _ in
                translationManager.translate(sourceText: speechRecognizer.transcript)
            }
            .onChange(of: translationManager.sourceLanguage) { _ in
                translationManager.translate(sourceText: speechRecognizer.transcript)
            }
        }
    }

    // MARK: - Status Card
    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(speechRecognizer.isConnectedToBroadcast ? Color.green.opacity(0.2) : (speechRecognizer.isMicMode ? Color.orange.opacity(0.2) : Color.blue.opacity(0.15)))
                        .frame(width: 52, height: 52)

                    Image(systemName: speechRecognizer.isConnectedToBroadcast ? "antenna.radiowaves.left.and.right" : (speechRecognizer.isMicMode ? "mic.fill" : "waveform.badge.magnifyingglass"))
                        .font(.system(size: 22))
                        .foregroundColor(speechRecognizer.isConnectedToBroadcast ? .green : (speechRecognizer.isMicMode ? .orange : .blue))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(speechRecognizer.isConnectedToBroadcast ? "Broadcast Active" : (speechRecognizer.isMicMode ? "Microphone Mode" : "Audio Capture"))
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(speechRecognizer.isRecognizing ? "Transcribing live • \(speechRecognizer.audioPacketsReceived) buffers" : "Ready • Tap button to broadcast")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                // Native Broadcast Picker Button
                ZStack {
                    Circle()
                        .fill(speechRecognizer.isConnectedToBroadcast ? Color.green : Color.blue)
                        .frame(width: 50, height: 50)
                        .shadow(color: (speechRecognizer.isConnectedToBroadcast ? Color.green : Color.blue).opacity(0.4), radius: 8, x: 0, y: 4)

                    BroadcastPickerRepresentable()
                        .frame(width: 48, height: 48)
                }
            }

            // Diagnostic status pill
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(speechRecognizer.isAuthorized ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(speechRecognizer.isAuthorized ? "Speech Authorized" : "Speech Auth Needed")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                Spacer()

                Text(speechRecognizer.statusMessage)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Translation Control Card (Language A ➔ Language B)
    private var translationControlCard: some View {
        VStack(spacing: 14) {
            // Header with toggle
            HStack {
                Label("Live Translation", systemImage: "globe")
                    .font(.subheadline.bold())
                    .foregroundColor(.cyan)

                Spacer()

                Toggle("", isOn: $translationManager.isTranslationEnabled)
                    .labelsHidden()
                    .tint(.cyan)
                    .onChange(of: translationManager.isTranslationEnabled) { _ in
                        translationManager.translate(sourceText: speechRecognizer.transcript)
                    }
            }

            // Language Selector Bar: [Source] ⇄ [Target]
            HStack(spacing: 10) {
                // Source Language Button
                Menu {
                    ForEach(TranslationManager.supportedLanguages) { lang in
                        Button(action: {
                            translationManager.setSource(lang)
                            speechRecognizer.updateLocale(Locale(identifier: lang.code))
                            translationManager.translate(sourceText: speechRecognizer.transcript)
                        }) {
                            HStack {
                                Text("\(lang.flag) \(lang.name)")
                                if lang.code == translationManager.sourceLanguage.code {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SPOKEN AUDIO")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.gray)
                        HStack(spacing: 6) {
                            Text(translationManager.sourceLanguage.flag)
                                .font(.headline)
                            Text(translationManager.sourceLanguage.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(12)
                }

                // Swap Button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        translationManager.swapLanguages()
                        speechRecognizer.updateLocale(Locale(identifier: translationManager.sourceLanguage.code))
                        translationManager.translate(sourceText: speechRecognizer.transcript)
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 38, height: 38)
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.cyan)
                    }
                }

                // Target Language Button
                Menu {
                    ForEach(TranslationManager.supportedLanguages) { lang in
                        Button(action: {
                            translationManager.setTarget(lang)
                            translationManager.translate(sourceText: speechRecognizer.transcript)
                        }) {
                            HStack {
                                Text("\(lang.flag) \(lang.name)")
                                if lang.code == translationManager.targetLanguage.code {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SUBTITLES")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.gray)
                        HStack(spacing: 6) {
                            Text(translationManager.targetLanguage.flag)
                                .font(.headline)
                            Text(translationManager.targetLanguage.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(12)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Caption Preview Box
    private var captionPreviewBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    translationManager.isTranslationEnabled && translationManager.sourceLanguage.langCode != translationManager.targetLanguage.langCode ? "Translated Subtitles (\(translationManager.targetLanguage.flag))" : "Live Captions",
                    systemImage: "text.bubble.fill"
                )
                .font(.subheadline.bold())
                .foregroundColor(translationManager.isTranslationEnabled ? .cyan : .gray)

                if translationManager.isTranslating {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.cyan)
                }

                Spacer()

                Button(action: { speechRecognizer.clear() }) {
                    Image(systemName: "trash")
                        .foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                // Primary Text: Translated Subtitle
                let hasTranslation = translationManager.isTranslationEnabled &&
                    !translationManager.translatedText.isEmpty &&
                    translationManager.sourceLanguage.langCode != translationManager.targetLanguage.langCode

                let displayText = hasTranslation
                    ? translationManager.translatedText
                    : speechRecognizer.transcript

                Text(displayText.isEmpty ? "Play a video or tap 'Test via Microphone' to see live translated subtitles..." : displayText)
                    .font(.system(size: CGFloat(fontSize), weight: .semibold, design: .rounded))
                    .foregroundColor(displayText.isEmpty ? .gray.opacity(0.7) : (hasTranslation ? .cyan : .white))
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Secondary Original Text
                if hasTranslation && !speechRecognizer.transcript.isEmpty {
                    Divider().background(Color.white.opacity(0.1))
                    HStack(spacing: 4) {
                        Text("\(translationManager.sourceLanguage.flag) Original:")
                            .font(.caption2.bold())
                            .foregroundColor(.gray)
                        Text(speechRecognizer.transcript)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 90)
            .padding(14)
            .background(Color.black.opacity(0.4))
            .cornerRadius(14)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Controls Grid
    private var controlsGrid: some View {
        VStack(spacing: 12) {
            // Floating Subtitles PiP button
            Button(action: { pipManager.togglePiP() }) {
                HStack {
                    Image(systemName: pipManager.isPiPActive ? "pip.exit" : "pip.enter")
                        .font(.headline)
                    Text(pipManager.isPiPActive ? "Exit Floating Subtitles" : "Open Floating Subtitles (PiP)")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)
            }

            // Quick Microphone Mode Toggle
            Button(action: { speechRecognizer.toggleMicMode() }) {
                HStack {
                    Image(systemName: speechRecognizer.isMicMode ? "stop.fill" : "mic.fill")
                    Text(speechRecognizer.isMicMode ? "Stop Microphone Mode" : "Test via Microphone (Speakers)")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(speechRecognizer.isMicMode ? .red : .orange)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(speechRecognizer.isMicMode ? Color.red.opacity(0.15) : Color.orange.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(speechRecognizer.isMicMode ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Settings Section
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
                .foregroundColor(.white)

            // Show Original Subtitle in PiP
            Toggle(isOn: $translationManager.showOriginalInPiP) {
                Text("Show Original Text in PiP")
                    .foregroundColor(.white)
            }
            .tint(.cyan)

            Divider().background(Color.white.opacity(0.1))

            // Subtitle Font Size Slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Subtitle Text Size")
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int(fontSize)) pt")
                        .foregroundColor(.gray)
                }
                Slider(value: $fontSize, in: 12...24, step: 1)
                    .tint(.cyan)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Translation ViewModifier
private struct TranslationTaskModifier: ViewModifier {
    @ObservedObject var translationManager = TranslationManager.shared
    @EnvironmentObject var speechRecognizer: SpeechRecognizer

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            content.translationTask(
                source: Locale.Language(identifier: translationManager.sourceLanguage.langCode),
                target: Locale.Language(identifier: translationManager.targetLanguage.langCode)
            ) { session in
                translationManager.activeSession = session
                if !speechRecognizer.transcript.isEmpty {
                    translationManager.translate(sourceText: speechRecognizer.transcript)
                }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
