package com.livesub.app.domain.model

/**
 * État immuable consommé par l'overlay flottant et l'écran principal.
 */
data class SubtitleUiState(
    val isRunning: Boolean = false,
    val currentSubtitle: SubtitleItem? = null,
    val activeLanguages: LanguagePair = LanguagePair(),
    val isMicFallback: Boolean = false,
    val fontSizeSp: Float = 18f,
    val backgroundOpacity: Float = 0.75f,
    val textColorHex: String = "#FFFFFF",
    val isCollapsed: Boolean = false,
    val errorMessage: String? = null
)
