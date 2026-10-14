package com.livesub.app.ml

import com.google.common.truth.Truth.assertThat
import com.livesub.app.domain.model.AudioChunk
import com.livesub.app.domain.model.SubtitleItem
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AudioPipelineSimulationTest {

    private val fakeTranslationEngine = object : TranslationEngine {
        override suspend fun translate(
            text: String,
            sourceLangCode: String,
            targetLangCode: String
        ): Result<String> {
            return if (text.contains("movie scene", ignoreCase = true)) {
                Result.success("Bonjour, bienvenue dans cette scène de film.")
            } else {
                Result.success("Traduction simulée : $text")
            }
        }

        override fun close() {}
    }

    @Test
    fun `end to end audio chunks stream to speech finalization and translation`() = runTest {
        val asrEngine = MockSherpaOnnxAsrEngine()
        val processor = StreamingAsrProcessor(asrEngine, this)

        val finalizedResults = mutableListOf<AsrResult>()
        val collectionJob = launch {
            processor.finalizedPhrases.collect {
                finalizedResults.add(it)
            }
        }

        // 1. Envoi de blocs de parole (signal vocal actif)
        val speechData = ShortArray(640) { 3000.toShort() }
        val speechChunk = AudioChunk(speechData, sampleRate = 16000, isSpeech = true)

        repeat(5) {
            processor.processChunk(speechChunk)
            testScheduler.advanceTimeBy(40)
        }

        // 2. Détection d'un silence (pause respiratoire / fin de phrase)
        val silenceData = ShortArray(640) { 0 }
        val silenceChunk = AudioChunk(silenceData, sampleRate = 16000, isSpeech = false)
        processor.processChunk(silenceChunk)

        // 3. Avancer le temps pour déclencher le timer de 350ms de fin de phrase
        testScheduler.advanceTimeBy(400)

        // 4. Vérification de la phrase finalisée par le processeur ASR
        assertThat(finalizedResults).isNotEmpty()
        val finalAsr = finalizedResults.first()
        assertThat(finalAsr.isFinal).isTrue()
        assertThat(finalAsr.text).contains("movie scene")

        // 5. Traduction neuronale
        val translationResult = fakeTranslationEngine.translate(
            text = finalAsr.text,
            sourceLangCode = "en",
            targetLangCode = "fr"
        )

        assertThat(translationResult.isSuccess).isTrue()
        val translatedText = translationResult.getOrThrow()
        assertThat(translatedText).isEqualTo("Bonjour, bienvenue dans cette scène de film.")

        // 6. Création de l'entité SubtitleItem et export
        val subtitle = SubtitleItem(
            sourceText = finalAsr.text,
            translatedText = translatedText,
            startTimeMs = finalAsr.startTimeMs,
            endTimeMs = finalAsr.endTimeMs,
            isFinal = true
        )

        assertThat(subtitle.translatedText).isNotEmpty()
        assertThat(subtitle.startTimeMs).isAtMost(subtitle.endTimeMs)

        val srtBlock = subtitle.toSrtBlock(1)
        assertThat(srtBlock).contains("Bonjour, bienvenue dans cette scène de film.")

        collectionJob.cancel()
        processor.release()
    }
}
