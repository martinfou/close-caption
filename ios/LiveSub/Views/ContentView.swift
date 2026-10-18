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
    @AppStorage("fontSize") private var fontSize: Double = 22.0

    @State private var downloadTrigger = 0
    @State private var pickerTrigger = 0
    @State private var showSettings = false

    private var isLive: Bool { speechRecognizer.isConnectedToBroadcast }

    public var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.06, blue: 0.11), Color(red: 0.10, green: 0.08, blue: 0.20)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                hiddenHosts

                ScrollView {
                    VStack(spacing: 16) {
                        statusHeader
                        languageCard
                        subtitleCard
                        actions
                    }
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("LiveSub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { settingsSheet }
            .onChange(of: speechRecognizer.transcript) { text in
                translationManager.translate(sourceText: text)
            }
            .onChange(of: translationManager.sourceLanguage) { lang in
                speechRecognizer.updateLocale(Locale(identifier: lang.code))
                translationManager.translate(sourceText: speechRecognizer.transcript)
            }
            .onChange(of: translationManager.targetLanguage) { _ in
                translationManager.translate(sourceText: speechRecognizer.transcript)
            }
            .onChange(of: translationManager.isTranslationEnabled) { _ in
                translationManager.translate(sourceText: speechRecognizer.transcript)
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
    }

    // MARK: Hidden hosts

    private var hiddenHosts: some View {
        ZStack {
            PiPSourceViewRepresentable(view: pipManager.sourceView)
                .frame(width: 1, height: 1)
                .opacity(0.01)

            BroadcastPickerRepresentable(trigger: $pickerTrigger)
                .frame(width: 44, height: 44)
                .allowsHitTesting(false)

            #if canImport(Translation)
            if #available(iOS 18.0, *) {
                LiveTranslationHost(
                    source: translationManager.sourceLanguage.langCode,
                    target: translationManager.targetLanguage.langCode
                )
                DownloadHost(trigger: $downloadTrigger)
            }
            #endif
        }
        .frame(width: 1, height: 1)
        .opacity(0.02)
    }

    // MARK: Status

    private var statusText: String {
        if speechRecognizer.isMicMode { return "Listening to microphone" }
        if isLive { return translationManager.isActiveTranslation ? "Translating live" : "Captioning live" }
        return "Ready"
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isLive || speechRecognizer.isMicMode ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Spacer()
            if translationManager.isActiveTranslation, !translationManager.engineStatus.isEmpty {
                Text(translationManager.engineStatus)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Language card

    private var languageCard: some View {
        VStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    languageMenu(title: "I'm hearing", selected: translationManager.sourceLanguage) {
                        translationManager.setSource($0)
                    }
                    swapButton
                    languageMenu(title: "Show subtitles in", selected: translationManager.targetLanguage) {
                        translationManager.setTarget($0)
                    }
                }
                VStack(spacing: 10) {
                    languageMenu(title: "I'm hearing", selected: translationManager.sourceLanguage) {
                        translationManager.setSource($0)
                    }
                    swapButton
                    languageMenu(title: "Show subtitles in", selected: translationManager.targetLanguage) {
                        translationManager.setTarget($0)
                    }
                }
            }

            Toggle("Translate", isOn: $translationManager.isTranslationEnabled)
                .tint(.cyan)
                .foregroundColor(.white)
        }
        .cardStyle()
    }

    private var swapButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                translationManager.swapLanguages()
            }
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.cyan)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .accessibilityLabel("Swap languages")
    }

    private func languageMenu(title: String, selected: AppLanguage, onSelect: @escaping (AppLanguage) -> Void) -> some View {
        Menu {
            ForEach(TranslationManager.supportedLanguages) { lang in
                Button {
                    onSelect(lang)
                } label: {
                    if lang.code == selected.code {
                        Label("\(lang.flag) \(lang.name)", systemImage: "checkmark")
                    } else {
                        Text("\(lang.flag) \(lang.name)")
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
                HStack(spacing: 6) {
                    Text(selected.flag).font(.title3)
                    Text(selected.name)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
        }
    }

    // MARK: Subtitle card

    private var subtitleCard: some View {
        let hasTranslation = translationManager.isActiveTranslation && !translationManager.translatedText.isEmpty
        let transcript = speechRecognizer.transcript
        let shown = hasTranslation ? translationManager.translatedText : transcript
        let placeholder = (isLive || speechRecognizer.isMicMode)
            ? "Listening for \(translationManager.sourceLanguage.name)…"
            : "Subtitles will appear here"

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live subtitles")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gray)
                Spacer()
                if translationManager.isTranslating { ProgressView().scaleEffect(0.7) }
                Button { speechRecognizer.clear() } label: {
                    Image(systemName: "trash").foregroundColor(.gray)
                }
                .accessibilityLabel("Clear")
            }

            Text(shown.isEmpty ? placeholder : shown)
                .font(.system(size: CGFloat(fontSize), weight: .semibold, design: .rounded))
                .foregroundColor(shown.isEmpty ? .gray.opacity(0.6) : (hasTranslation ? .cyan : .white))
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)

            if hasTranslation, !transcript.isEmpty {
                Divider().background(Color.white.opacity(0.1))
                Text(transcript)
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .lineLimit(3)
            } else if translationManager.isActiveTranslation, !transcript.isEmpty {
                Text("Translating…")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .cardStyle()
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 12) {
            Button { pickerTrigger += 1 } label: {
                Label(isLive ? "Broadcasting – tap to stop" : "Start Live Subtitles",
                      systemImage: isLive ? "stop.circle.fill" : "play.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(
                                colors: isLive ? [.red, .orange] : [.blue, .purple],
                                startPoint: .leading, endPoint: .trailing))
                    )
            }

            Text("Tap Start, choose “LiveSub Broadcast”, then open YouTube or any video.")
                .font(.footnote)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                secondaryButton(
                    title: pipManager.isPiPActive ? "Close floating" : "Floating window",
                    icon: pipManager.isPiPActive ? "pip.exit" : "pip.enter",
                    color: .cyan
                ) { pipManager.togglePiP() }

                secondaryButton(
                    title: speechRecognizer.isMicMode ? "Stop mic" : "Test with mic",
                    icon: speechRecognizer.isMicMode ? "stop.fill" : "mic.fill",
                    color: speechRecognizer.isMicMode ? .red : .orange
                ) { speechRecognizer.toggleMicMode() }
            }
        }
    }

    private func secondaryButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.15)))
        }
    }

    // MARK: Settings sheet

    private var settingsSheet: some View {
        NavigationView {
            Form {
                Section("Subtitles") {
                    VStack(alignment: .leading) {
                        Text("Text size: \(Int(fontSize)) pt")
                        Slider(value: $fontSize, in: 14...34, step: 1)
                    }
                    Toggle("Show original in floating window", isOn: $translationManager.showOriginalInPiP)
                }

                Section(header: Text("Offline translation"),
                        footer: Text("Download \(translationManager.sourceLanguage.name) → \(translationManager.targetLanguage.name) so translation works without internet.")) {
                    Button {
                        showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { downloadTrigger += 1 }
                    } label: {
                        Label("Download language pack", systemImage: "arrow.down.circle")
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open iOS Settings", systemImage: "gear")
                    }
                }

                Section("Diagnostics") {
                    row("Speech access", speechRecognizer.isAuthorized ? "Allowed" : "Needed")
                    row("Status", speechRecognizer.statusMessage)
                    row("Audio buffers", "\(speechRecognizer.audioPacketsReceived)")
                    if !speechRecognizer.debugInfo.isEmpty {
                        Text(speechRecognizer.debugInfo)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary).multilineTextAlignment(.trailing)
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self.padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1))
            )
    }
}

#if canImport(Translation)
@available(iOS 18.0, *)
private struct LiveTranslationHost: View {
    let source: String
    let target: String

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(
                source: Locale.Language(identifier: source),
                target: Locale.Language(identifier: target)
            ) { session in
                await TranslationManager.shared.runSession(session)
            }
    }
}

@available(iOS 18.0, *)
private struct DownloadHost: View {
    @Binding var trigger: Int
    @ObservedObject private var tm = TranslationManager.shared
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(configuration) { session in
                do { try await session.prepareTranslation() }
                catch { print("[LiveSub] prepareTranslation error: \(error)") }
            }
            .onChange(of: trigger) { _ in
                if configuration == nil {
                    configuration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: tm.sourceLanguage.langCode),
                        target: Locale.Language(identifier: tm.targetLanguage.langCode)
                    )
                } else {
                    configuration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: tm.sourceLanguage.langCode),
                        target: Locale.Language(identifier: tm.targetLanguage.langCode)
                    )
                }
                configuration?.invalidate()
            }
    }
}
#endif
