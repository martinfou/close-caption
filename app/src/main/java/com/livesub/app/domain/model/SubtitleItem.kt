package com.livesub.app.domain.model

import java.util.Locale
import java.util.UUID

/**
 * Entité représentant une réplique de sous-titre transcrite et traduite avec horodatage.
 */
data class SubtitleItem(
    val id: String = UUID.randomUUID().toString(),
    val sourceText: String,
    val translatedText: String,
    val startTimeMs: Long,
    val endTimeMs: Long,
    val isFinal: Boolean = false
) {
    /**
     * Formate l'élément selon la norme standard SubRip (.srt) :
     * 1
     * 00:01:23,450 --> 00:01:25,800
     * Texte traduit
     */
    fun toSrtBlock(index: Int): String {
        return buildString {
            appendLine(index)
            append(formatSrtTime(startTimeMs))
            append(" --> ")
            appendLine(formatSrtTime(endTimeMs))
            appendLine(translatedText)
        }
    }

    companion object {
        fun formatSrtTime(millis: Long): String {
            val totalSeconds = millis / 1000
            val hours = totalSeconds / 3600
            val minutes = (totalSeconds % 3600) / 60
            val seconds = totalSeconds % 60
            val ms = millis % 1000
            return String.format(Locale.US, "%02d:%02d:%02d,%03d", hours, minutes, seconds, ms)
        }
    }
}
