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
            List {
                statusSection
                languageSection
                subtitleSection
                actionsSection
            }
            .listStyle(.insetGrouped)
            .background(hiddenHosts)
            .navigationTitle("LiveSub")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
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

    private func binding(get: @escaping () -> AppLanguage, set: @escaping (AppLanguage) -> Void) -> Binding<AppLanguage> {
        Binding(get: get, set: set)
    }

    private var statusSection: some View {
        Section {
            HStack {
                Label {
                    Text(statusText)
                } icon: {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(isLive || speechRecognizer.isMicMode ? Color.green : Color.secondary)
                }
                Spacer()
                if translationManager.isActiveTranslation, !translationManager.engineStatus.isEmpty {
                    Text(translationManager.engineStatus).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Language section

    private var languageSection: some View {
        Section {
            Picker("I'm hearing", selection: binding(get: { translationManager.sourceLanguage }, set: { translationManager.setSource($0) })) {
                ForEach(TranslationManager.supportedLanguages) { Text("\($0.flag) \($0.name)").tag($0) }
            }
            Picker("Subtitles in", selection: binding(get: { translationManager.targetLanguage }, set: { translationManager.setTarget($0) })) {
                ForEach(TranslationManager.supportedLanguages) { Text("\($0.flag) \($0.name)").tag($0) }
            }
            Button {
                translationManager.swapLanguages()
            } label: {
                Label("Swap languages", systemImage: "arrow.up.arrow.down")
            }
            Toggle("Translate", isOn: $translationManager.isTranslationEnabled)
        } header: {
            Text("Languages")
        }
    }

    // MARK: Subtitle section

    private var subtitleSection: some View {
        let hasTranslation = translationManager.isActiveTranslation && !translationManager.translatedText.isEmpty
        let transcript = speechRecognizer.transcript
        let shown = hasTranslation ? translationManager.translatedText : transcript
        let placeholder = (isLive || speechRecognizer.isMicMode)
            ? "Listening for \(translationManager.sourceLanguage.name)…"
            : "Subtitles will appear here"

        return Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(shown.isEmpty ? placeholder : shown)
                    .font(.system(size: CGFloat(fontSize), weight: .semibold, design: .default))
                    .foregroundStyle(shown.isEmpty ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                if hasTranslation, !transcript.isEmpty {
                    Text(transcript)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(.vertical, 4)
            if !speechRecognizer.transcript.isEmpty {
                Button("Clear", role: .destructive) { speechRecognizer.clear() }
            }
        } header: {
            HStack {
                Text("Live Subtitles")
                if translationManager.isTranslating { ProgressView().controlSize(.mini) }
            }
        }
    }

    // MARK: Actions

    private var actionsSection: some View {
        Section {
            Button { pickerTrigger += 1 } label: {
                Label(isLive ? "Stop Broadcast" : "Start Live Subtitles",
                      systemImage: isLive ? "stop.circle.fill" : "play.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(isLive ? .red : .accentColor)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Button { pipManager.togglePiP() } label: {
                Label(pipManager.isPiPActive ? "Close Floating Window" : "Floating Window",
                      systemImage: pipManager.isPiPActive ? "pip.exit" : "pip.enter")
            }
            Button { speechRecognizer.toggleMicMode() } label: {
                Label(speechRecognizer.isMicMode ? "Stop Microphone" : "Test with Microphone",
                      systemImage: speechRecognizer.isMicMode ? "stop.fill" : "mic.fill")
            }
        } footer: {
            Text("Tap Start, choose “LiveSub Broadcast”, then open YouTube or any video.")
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
