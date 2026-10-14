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
) {
    val sourceCode: String get() = source.code
    val targetCode: String get() = target.code

    companion object {
        fun fromCodes(sourceCode: String, targetCode: String): LanguagePair {
            val src = Language.SUPPORTED_LANGUAGES.find { it.code == sourceCode }
                ?: Language(sourceCode, sourceCode, "🌐")
            val tgt = Language.SUPPORTED_LANGUAGES.find { it.code == targetCode }
                ?: Language(targetCode, targetCode, "🌐")
            return LanguagePair(source = src, target = tgt)
        }
    }
}

