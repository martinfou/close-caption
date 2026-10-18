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
    @State private var downloadMessage: String?
    @State private var showDownloadPrompt = false
    @State private var packInstalled: Bool?

    /// Checks whether the on-device pack for the selected pair is installed; optionally suggests downloading it.
    private func checkPack(prompt: Bool) {
        #if canImport(Translation)
        guard #available(iOS 18.0, *) else { return }
        let src = Locale.Language(identifier: translationManager.sourceLanguage.langCode)
        let tgt = Locale.Language(identifier: translationManager.targetLanguage.langCode)
        guard translationManager.isActiveTranslation else { packInstalled = nil; return }
        Task { @MainActor in
            let status = await LanguageAvailability().status(from: src, to: tgt)
            switch status {
            case .installed:
                packInstalled = true
            case .supported:
                packInstalled = false
                if prompt { showDownloadPrompt = true }
            @unknown default:
                packInstalled = nil
            }
        }
        #endif
    }

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
            .downloadHost(trigger: downloadTrigger, message: $downloadMessage)
            .alert(downloadMessage ?? "", isPresented: Binding(get: { downloadMessage != nil }, set: { if !$0 { downloadMessage = nil } })) {
                Button("OK", role: .cancel) {}
            }
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
            .onAppear { checkPack(prompt: false) }
            .onReceive(NotificationCenter.default.publisher(for: .packChanged)) { _ in
                checkPack(prompt: false)
                translationManager.resetFailures()
                translationManager.translate(sourceText: speechRecognizer.transcript)
            }
            .alert("Download language pack?", isPresented: $showDownloadPrompt) {
                Button("Download") { downloadTrigger += 1 }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("\(translationManager.sourceLanguage.name) → \(translationManager.targetLanguage.name) isn't on this iPad yet. Download it for fast, private, offline translation.")
            }
            .onChange(of: speechRecognizer.transcript) { text in
                translationManager.translate(sourceText: text)
            }
            .onChange(of: translationManager.sourceLanguage) { lang in
                checkPack(prompt: true)
                speechRecognizer.updateLocale(Locale(identifier: lang.code))
                translationManager.translate(sourceText: speechRecognizer.transcript)
            }
            .onChange(of: translationManager.targetLanguage) { _ in
                checkPack(prompt: true)
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
                .id("\(translationManager.sourceLanguage.langCode)->\(translationManager.targetLanguage.langCode)")
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
        } footer: {
            if packInstalled == false {
                Button("Offline pack not installed – tap to download") { downloadTrigger += 1 }
                    .font(.footnote)
            } else if packInstalled == true {
                Text("Offline pack installed.")
            }
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
            VStack(alignment: .leading, spacing: 6) {
                Text(shown.isEmpty ? placeholder : shown)
                    .font(.system(size: CGFloat(fontSize), weight: .semibold, design: .default))
                    .foregroundStyle(shown.isEmpty ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, minHeight: 65, alignment: .topLeading)

                if hasTranslation, translationManager.showOriginalInPiP, !transcript.isEmpty {
                    Text(transcript)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
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
                Section("Subtitles Appearance") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Text size")
                            Spacer()
                            Text("\(Int(fontSize)) pt").foregroundStyle(.secondary)
                        }
                        Slider(value: $fontSize, in: 14...34, step: 1)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Reading dwell buffer")
                            Spacer()
                            Text(String(format: "%.1f s", translationManager.dwellSeconds)).foregroundStyle(.secondary)
                        }
                        Slider(value: $translationManager.dwellSeconds, in: 1.0...6.0, step: 0.5)
                        Text("Holds the previous subtitle on screen so fast-spoken sentences don't vanish before you finish reading.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                await TranslationManager.shared.runSession(session, source: source, target: target)
            }
    }
}

@available(iOS 18.0, *)
private struct DownloadModifier: ViewModifier {
    let trigger: Int
    @Binding var message: String?
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                do {
                    try await session.prepareTranslation()
                    message = "Language pack is ready for offline use."
                    NotificationCenter.default.post(name: .packChanged, object: nil)
                } catch {
                    message = "Couldn't download the language pack: \(error.localizedDescription)"
                }
            }
            .onChange(of: trigger) { _ in
                let tm = TranslationManager.shared
                if configuration == nil {
                    configuration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: tm.sourceLanguage.langCode),
                        target: Locale.Language(identifier: tm.targetLanguage.langCode))
                } else {
                    configuration?.source = Locale.Language(identifier: tm.sourceLanguage.langCode)
                    configuration?.target = Locale.Language(identifier: tm.targetLanguage.langCode)
                    configuration?.invalidate()
                }
            }
    }
}
#endif

private extension View {
    @ViewBuilder
    func downloadHost(trigger: Int, message: Binding<String?>) -> some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            self.modifier(DownloadModifier(trigger: trigger, message: message))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

extension Notification.Name { static let packChanged = Notification.Name("LiveSubPackChanged") }
