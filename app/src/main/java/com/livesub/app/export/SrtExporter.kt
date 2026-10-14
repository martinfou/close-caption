package com.livesub.app.export

import android.content.Context
import android.os.Environment
import com.livesub.app.domain.model.SubtitleItem
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStreamWriter
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Gestionnaire d'exportation des répliques de sous-titres au format SubRip (.srt).
 */
object SrtExporter {

    /**
     * Génère le contenu texte brut conforme aux spécifications SubRip (.srt).
     */
    fun buildSrtContent(subtitles: List<SubtitleItem>): String {
        return buildString {
            subtitles.forEachIndexed { index, item ->
                append(item.toSrtBlock(index + 1))
                appendLine()
            }
        }.trimEnd() + "\n"
    }

    /**
     * Exporte la liste des sous-titres dans un fichier `.srt` horodaté dans le répertoire Downloads ou documents.
     */
    fun exportToFile(
        context: Context,
        subtitles: List<SubtitleItem>,
        baseFileName: String = "LiveSub_Session"
    ): Result<File> {
        if (subtitles.isEmpty()) {
            return Result.failure(IllegalArgumentException("Aucun sous-titre à exporter dans cette session."))
        }

        return try {
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            val fileName = "${baseFileName}_$timestamp.srt"

            // Répertoire de destination : Répertoire de documents externe public ou cache externe
            val outputDir = context.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS) ?: context.filesDir
            if (!outputDir.exists()) {
                outputDir.mkdirs()
            }

            val file = File(outputDir, fileName)
            val srtContent = buildSrtContent(subtitles)

            OutputStreamWriter(FileOutputStream(file), StandardCharsets.UTF_8).use { writer ->
                writer.write(srtContent)
                writer.flush()
            }

            Result.success(file)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
