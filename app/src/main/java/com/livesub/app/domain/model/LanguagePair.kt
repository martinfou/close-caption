package com.livesub.app.domain.model

/**
 * Représente une langue supportée pour la transcription et la traduction.
 */
data class Language(
    val code: String,
    val displayName: String,
    val flagEmoji: String
) {
    companion object {
        val SUPPORTED_LANGUAGES = listOf(
            Language("fr", "Français", "🇫🇷"),
            Language("en", "English", "🇺🇸"),
            Language("ja", "日本語 (Japonais)", "🇯🇵"),
            Language("es", "Español", "🇪🇸"),
            Language("ko", "한국어 (Coréen)", "🇰🇷"),
            Language("de", "Deutsch", "🇩🇪"),
            Language("it", "Italiano", "🇮🇹"),
            Language("pt", "Português", "🇧🇷"),
            Language("zh", "中文 (Chinois)", "🇨🇳")
        )

        val DEFAULT_SOURCE = Language("en", "English", "🇺🇸")
        val DEFAULT_TARGET = Language("fr", "Français", "🇫🇷")
    }
}

data class LanguagePair(
    val source: Language = Language.DEFAULT_SOURCE,
    val target: Language = Language.DEFAULT_TARGET
)
