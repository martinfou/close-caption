package com.livesub.app.export

import com.google.common.truth.Truth.assertThat
import com.livesub.app.domain.model.SubtitleItem
import org.junit.Test

class SrtExporterTest {

    @Test
    fun `formatSrtTime formats milliseconds into standard SubRip timestamp`() {
        assertThat(SubtitleItem.formatSrtTime(0L)).isEqualTo("00:00:00,000")
        assertThat(SubtitleItem.formatSrtTime(1234L)).isEqualTo("00:00:01,234")
        assertThat(SubtitleItem.formatSrtTime(65432L)).isEqualTo("00:01:05,432")
        assertThat(SubtitleItem.formatSrtTime(3661500L)).isEqualTo("01:01:01,500")
    }

    @Test
    fun `buildSrtContent formats a single subtitle item compliant with SRT standard`() {
        val item = SubtitleItem(
            sourceText = "Hello world",
            translatedText = "Bonjour le monde",
            startTimeMs = 1500L,
            endTimeMs = 4000L,
            isFinal = true
        )

        val srtOutput = SrtExporter.buildSrtContent(listOf(item))

        val expected = """
            1
            00:00:01,500 --> 00:00:04,000
            Bonjour le monde
        """.trimIndent() + "\n"

        assertThat(srtOutput.trim()).isEqualTo(expected.trim())
    }

    @Test
    fun `buildSrtContent formats multiple sequential subtitle items with correct numbering`() {
        val items = listOf(
            SubtitleItem(
                sourceText = "Good morning",
                translatedText = "Bonjour",
                startTimeMs = 1000L,
                endTimeMs = 2500L,
                isFinal = true
            ),
            SubtitleItem(
                sourceText = "How are you doing today?",
                translatedText = "Comment allez-vous aujourd'hui ?",
                startTimeMs = 2600L,
                endTimeMs = 5200L,
                isFinal = true
            )
        )

        val srtOutput = SrtExporter.buildSrtContent(items)

        assertThat(srtOutput).contains("1\n00:00:01,000 --> 00:00:02,500\nBonjour")
        assertThat(srtOutput).contains("2\n00:00:02,600 --> 00:00:05,200\nComment allez-vous aujourd'hui ?")
    }

    @Test
    fun `buildSrtContent with empty list returns clean empty format`() {
        val srtOutput = SrtExporter.buildSrtContent(emptyList())
        assertThat(srtOutput.trim()).isEmpty()
    }
}
