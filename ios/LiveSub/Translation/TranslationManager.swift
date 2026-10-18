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
    public let code: String          // e.g. "en-US"
    public let langCode: String      // e.g. "en"
    public let name: String          // e.g. "English"
    public let flag: String          // e.g. "🇺🇸"

    public init(code: String, langCode: String, name: String, flag: String) {
        self.id = code
        self.code = code
        self.langCode = langCode
        self.name = name
        self.flag = flag
    }
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

    @AppStorage("sourceLanguageCode") public var sourceCode: String = "es-ES" {
        didSet { updateSelectedLanguages() }
    }
    @AppStorage("targetLanguageCode") public var targetCode: String = "en-US" {
        didSet { updateSelectedLanguages() }
    }
    @AppStorage("isTranslationEnabled") public var isTranslationEnabled: Bool = true
    @AppStorage("showOriginalInPiP") public var showOriginalInPiP: Bool = true

    @Published public var sourceLanguage: AppLanguage
    @Published public var targetLanguage: AppLanguage
    @Published public var translatedText: String = ""
    @Published public var isTranslating: Bool = false
    @Published public var translationStatus: String = "Ready"

    #if canImport(Translation)
    private var _activeSession: Any?
    @available(iOS 18.0, *)
    public var activeSession: TranslationSession? {
        get { _activeSession as? TranslationSession }
        set { _activeSession = newValue }
    }
    #endif

    private var translationTask: Task<Void, Never>?
    private var lastTranslatedInput: String = ""

    public init() {
        let initialSource = Self.supportedLanguages.first { $0.code == "es-ES" } ?? Self.supportedLanguages[1]
        let initialTarget = Self.supportedLanguages.first { $0.code == "en-US" } ?? Self.supportedLanguages[0]
        self.sourceLanguage = initialSource
        self.targetLanguage = initialTarget
        updateSelectedLanguages()
    }

    private func updateSelectedLanguages() {
        if let s = Self.supportedLanguages.first(where: { $0.code == sourceCode }) {
            self.sourceLanguage = s
        }
        if let t = Self.supportedLanguages.first(where: { $0.code == targetCode }) {
            self.targetLanguage = t
        }
    }

    public func setSource(_ lang: AppLanguage) {
        sourceCode = lang.code
        sourceLanguage = lang
        triggerRetranslation()
    }

    public func setTarget(_ lang: AppLanguage) {
        targetCode = lang.code
        targetLanguage = lang
        triggerRetranslation()
    }

    public func swapLanguages() {
        let oldSource = sourceLanguage
        let oldTarget = targetLanguage
        setSource(oldTarget)
        setTarget(oldSource)
    }

    public func triggerRetranslation() {
        lastTranslatedInput = ""
        #if canImport(Translation)
        _activeSession = nil
        #endif
    }

    public func translate(sourceText: String) {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            translatedText = ""
            return
        }

        // If translation is turned off or languages match, mirror source
        guard isTranslationEnabled, sourceLanguage.langCode != targetLanguage.langCode else {
            translatedText = trimmed
            return
        }

        guard trimmed != lastTranslatedInput else { return }
        lastTranslatedInput = trimmed

        translationTask?.cancel()
        translationTask = Task { @MainActor in
            isTranslating = true

            #if canImport(Translation)
            if #available(iOS 18.0, *) {
                if let session = activeSession {
                    do {
                        let response = try await session.translate(trimmed)
                        if !Task.isCancelled {
                            self.translatedText = response.targetText
                            self.translationStatus = "Live translated"
                            self.isTranslating = false
                        }
                        return
                    } catch {
                        print("[TranslationManager] Session translate error: \(error)")
                    }
                }
            }
            #endif

            if !Task.isCancelled {
                self.translatedText = trimmed
                self.isTranslating = false
            }
        }
    }
}
