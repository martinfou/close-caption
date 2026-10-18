//
//  TranslationManager.swift
//  LiveSub
//
import Foundation
import SwiftUI
import Combine

#if canImport(Translation)
import Translation
#endif

public struct AppLanguage: Identifiable, Hashable {
    public let id: String
    public let code: String          // speech locale, e.g. "en-US"
    public let langCode: String      // translation language, e.g. "en"
    public let name: String
    public let flag: String

    public init(code: String, langCode: String, name: String, flag: String) {
        self.id = code
        self.code = code
        self.langCode = langCode
        self.name = name
        self.flag = flag
    }

    /// Language code understood by the online fallback translator.
    var onlineCode: String { langCode == "zh-Hans" ? "zh-CN" : langCode }
}

@MainActor
public final class TranslationManager: ObservableObject {
    public static let shared = TranslationManager()

    public static let supportedLanguages: [AppLanguage] = [
        AppLanguage(code: "en-US", langCode: "en", name: "English", flag: "🇺🇸"),
        AppLanguage(code: "es-ES", langCode: "es", name: "Español", flag: "🇪🇸"),
        AppLanguage(code: "fr-FR", langCode: "fr", name: "Français", flag: "🇫🇷"),
        AppLanguage(code: "de-DE", langCode: "de", name: "Deutsch", flag: "🇩🇪"),
        AppLanguage(code: "ja-JP", langCode: "ja", name: "日本語", flag: "🇯🇵"),
        AppLanguage(code: "zh-CN", langCode: "zh-Hans", name: "中文", flag: "🇨🇳"),
        AppLanguage(code: "it-IT", langCode: "it", name: "Italiano", flag: "🇮🇹"),
        AppLanguage(code: "pt-BR", langCode: "pt", name: "Português", flag: "🇧🇷"),
        AppLanguage(code: "ko-KR", langCode: "ko", name: "한국어", flag: "🇰🇷"),
        AppLanguage(code: "ru-RU", langCode: "ru", name: "Русский", flag: "🇷🇺"),
        AppLanguage(code: "ar-SA", langCode: "ar", name: "العربية", flag: "🇸🇦"),
        AppLanguage(code: "nl-NL", langCode: "nl", name: "Nederlands", flag: "🇳🇱")
    ]

    // MARK: Persisted settings (published so SwiftUI updates immediately)

    @Published public var isTranslationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTranslationEnabled, forKey: "isTranslationEnabled")
            resetPending()
        }
    }
    @Published public var showOriginalInPiP: Bool {
        didSet { UserDefaults.standard.set(showOriginalInPiP, forKey: "showOriginalInPiP") }
    }
    @Published public private(set) var sourceLanguage: AppLanguage
    @Published public private(set) var targetLanguage: AppLanguage

    // MARK: Output & Display Pacing (Dwell Buffer)

    @Published public var translatedText: String = ""
    @Published public var isTranslating: Bool = false
    /// Human readable engine state, e.g. "On-device" / "Online" / "Offline – showing original".
    @Published public var engineStatus: String = ""

    /// Subtitle linger / dwell buffer time in seconds (Default 3.0s, configurable in Settings)
    @Published public var dwellSeconds: Double {
        didSet { UserDefaults.standard.set(dwellSeconds, forKey: "subtitleDwellSeconds") }
    }

    public var sourceCode: String { sourceLanguage.code }
    public var targetCode: String { targetLanguage.code }

    public var isActiveTranslation: Bool {
        isTranslationEnabled && sourceLanguage.langCode != targetLanguage.langCode
    }

    // MARK: Internals

    private var generation = 0
    private var lastRequested = ""
    private var lastTranscript = ""

    private var appleContinuation: AsyncStream<String>.Continuation?
    private var appleReady = false
    private var appleFailures = 0

    private var onlineTask: Task<Void, Never>?
    private var pendingOnline: String?
    private var lastOnlineTime = Date.distantPast

    public init() {
        let defaults = UserDefaults.standard
        let src = defaults.string(forKey: "sourceLanguageCode") ?? "en-US"
        let tgt = defaults.string(forKey: "targetLanguageCode") ?? "fr-FR"
        self.sourceLanguage = Self.supportedLanguages.first { $0.code == src } ?? Self.supportedLanguages[0]
        self.targetLanguage = Self.supportedLanguages.first { $0.code == tgt } ?? Self.supportedLanguages[2]
        self.isTranslationEnabled = defaults.object(forKey: "isTranslationEnabled") as? Bool ?? true
        self.showOriginalInPiP = defaults.object(forKey: "showOriginalInPiP") as? Bool ?? false
        let savedDwell = defaults.double(forKey: "subtitleDwellSeconds")
        self.dwellSeconds = savedDwell > 0 ? savedDwell : 3.0
    }

    // MARK: Language selection

    public func setSource(_ lang: AppLanguage) {
        sourceLanguage = lang
        UserDefaults.standard.set(lang.code, forKey: "sourceLanguageCode")
        resetPending()
    }

    public func setTarget(_ lang: AppLanguage) {
        targetLanguage = lang
        UserDefaults.standard.set(lang.code, forKey: "targetLanguageCode")
        resetPending()
    }

    public func swapLanguages() {
        let s = sourceLanguage, t = targetLanguage
        setSource(t)
        setTarget(s)
    }

    public func resetFailures() {
        appleFailures = 0
    }

    /// Language changed: discard stale work and the old translation.
    private func resetPending() {
        generation += 1
        clearDwellTask?.cancel()
        clearDwellTask = nil
        lastRequested = ""
        pendingOnline = nil
        translatedText = ""
        appleFailures = 0
        appleReady = false
        appleContinuation?.finish()
        appleContinuation = nil
        onlineTask?.cancel()
        onlineTask = nil
    }

    private var clearDwellTask: Task<Void, Never>?

    /// Updates the single translated subtitle text and resets the dwell pause timer
    private func updateTranslationOutput(_ newText: String) {
        let clean = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        clearDwellTask?.cancel()
        self.translatedText = clean

        // After speech stops, hold this subtitle for `dwellSeconds` before clearing it
        let linger = dwellSeconds
        let capturedGen = generation
        clearDwellTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(linger * 1_000_000_000))
            guard let self = self, self.generation == capturedGen else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                self.translatedText = ""
            }
        }
    }

    // MARK: Translation entry point

    public func translate(sourceText: String) {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        lastTranscript = text

        guard !text.isEmpty else { return }
        guard isActiveTranslation else { translatedText = ""; return }
        guard text != lastRequested else { return }
        lastRequested = text
        isTranslating = true

        if appleReady && appleFailures < 2 {
            appleContinuation?.yield(text)          // newest-only buffer: never queues up
        } else {
            scheduleOnline(text)
        }
    }

    // MARK: Apple on-device engine (runs inside the system translationTask closure)

    #if canImport(Translation)
    @available(iOS 18.0, *)
    public func runSession(_ session: TranslationSession, source: String, target: String) async {
        guard source == sourceLanguage.langCode && target == targetLanguage.langCode else { return }

        var cont: AsyncStream<String>.Continuation!
        let stream = AsyncStream<String>(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        appleContinuation?.finish()
        appleContinuation = cont
        appleReady = true
        appleFailures = 0
        defer {
            appleReady = false
            cont.finish()
        }

        if !lastTranscript.isEmpty && isActiveTranslation {
            lastRequested = lastTranscript
            cont.yield(lastTranscript)
        }

        for await text in stream {
            let gen = generation
            do {
                let response = try await session.translate(text)
                guard gen == generation else { continue }
                updateTranslationOutput(response.targetText)
                engineStatus = "On-device"
                isTranslating = false
                appleFailures = 0
            } catch {
                if Task.isCancelled { break }
                appleFailures += 1
                print("[Translation] On-device failed (\(appleFailures)): \(error)")
                lastRequested = ""
                scheduleOnline(text)
            }
        }
    }
    #endif

    // MARK: Online fallback (throttled, keeps last good translation on failure)

    private func scheduleOnline(_ text: String) {
        pendingOnline = text
        guard onlineTask == nil else { return }

        onlineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.pendingOnline != nil {
                let wait = 0.3 - Date().timeIntervalSince(self.lastOnlineTime)
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }

                guard let text = self.pendingOnline else { break }
                self.pendingOnline = nil
                self.lastOnlineTime = Date()
                let gen = self.generation

                let result = await Self.fetchOnline(
                    text: text,
                    from: self.sourceLanguage.onlineCode,
                    to: self.targetLanguage.onlineCode
                )
                guard gen == self.generation else { continue }

                if let result {
                    self.updateTranslationOutput(result)
                    self.engineStatus = "Online"
                    self.isTranslating = false
                } else {
                    // Keep whatever translation we already have; allow a retry on the next update.
                    self.engineStatus = "Offline – retrying"
                    self.lastRequested = ""
                    self.isTranslating = false
                }
            }
            self.onlineTask = nil
        }
    }

    private nonisolated static func fetchOnline(text: String, from: String, to: String) async -> String? {
        if let googleResult = await fetchGoogle(text: text, from: from, to: to) {
            return googleResult
        }
        return await fetchMyMemory(text: text, from: from, to: to)
    }

    private nonisolated static func fetchGoogle(text: String, from: String, to: String) async -> String? {
        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        comps.queryItems = [
            URLQueryItem(name: "client", value: "dict-chrome-ex"),
            URLQueryItem(name: "sl", value: from),
            URLQueryItem(name: "tl", value: to),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        guard let url = comps.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 4

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                  let sentences = json.first as? [[Any]] else { return nil }
            let translated = sentences.compactMap { $0.first as? String }.joined()
            return translated.isEmpty ? nil : translated
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchMyMemory(text: String, from: String, to: String) async -> String? {
        var comps = URLComponents(string: "https://api.mymemory.translated.net/get")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "\(from)|\(to)")
        ]
        guard let url = comps.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let respData = json["responseData"] as? [String: Any],
                  let translated = respData["translatedText"] as? String else { return nil }
            let clean = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        } catch {
            return nil
        }
    }
}
