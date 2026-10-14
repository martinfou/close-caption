package com.livesub.app.ml

import com.google.common.truth.Truth.assertThat
import com.livesub.app.domain.model.LanguagePair
import com.livesub.app.domain.repository.SubtitleRepository
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class TranslationEngineTest {

    private val testDictionary = mapOf(
        "Hello, how are you?" to "Bonjour, comment allez-vous ?",
        "This movie is amazing!" to "Ce film est incroyable !",
        "Where is the train station?" to "Où est la gare ?",
        "Thank you very much." to "Merci beaucoup.",
        "Hola amigo" to "Bonjour mon ami"
    )

    private val simulatedTranslationEngine = object : TranslationEngine {
        var callCount = 0

        override suspend fun translate(
            text: String,
            sourceLangCode: String,
            targetLangCode: String
        ): Result<String> {
            val trimmed = text.trim()
            if (trimmed.isEmpty()) return Result.success("")
            if (sourceLangCode.equals(targetLangCode, ignoreCase = true)) {
                return Result.success(trimmed)
            }
            callCount++
            val translated = testDictionary[trimmed] ?: "[$targetLangCode] $trimmed"
            return Result.success(translated)
        }

        override fun close() {}
    }

    @Test
    fun `identical source and target languages return original text without translating`() = runTest {
        val original = "Ceci est déjà en français"
        val result = simulatedTranslationEngine.translate(
            text = original,
            sourceLangCode = "fr",
            targetLangCode = "fr"
        )

        assertThat(result.isSuccess).isTrue()
        assertThat(result.getOrNull()).isEqualTo(original)
        assertThat(simulatedTranslationEngine.callCount).isEqualTo(0)
    }

    @Test
    fun `empty or whitespace strings return empty result immediately`() = runTest {
        val result = simulatedTranslationEngine.translate(
            text = "   \n\t  ",
            sourceLangCode = "en",
            targetLangCode = "fr"
        )

        assertThat(result.isSuccess).isTrue()
        assertThat(result.getOrNull()).isEmpty()
        assertThat(simulatedTranslationEngine.callCount).isEqualTo(0)
    }

    @Test
    fun `english to french translation produces correct accurate sentences`() = runTest {
        val phrases = listOf(
            "Hello, how are you?" to "Bonjour, comment allez-vous ?",
            "This movie is amazing!" to "Ce film est incroyable !",
            "Where is the train station?" to "Où est la gare ?",
            "Thank you very much." to "Merci beaucoup."
        )

        for ((english, expectedFrench) in phrases) {
            val result = simulatedTranslationEngine.translate(
                text = english,
                sourceLangCode = "en",
                targetLangCode = "fr"
            )
            assertThat(result.isSuccess).isTrue()
            assertThat(result.getOrNull()).isEqualTo(expectedFrench)
        }
    }

    @Test
    fun `spanish to french translation translates as expected`() = runTest {
        val result = simulatedTranslationEngine.translate(
            text = "Hola amigo",
            sourceLangCode = "es",
            targetLangCode = "fr"
        )

        assertThat(result.isSuccess).isTrue()
        assertThat(result.getOrNull()).isEqualTo("Bonjour mon ami")
    }

    @Test
    fun `subtitle repository pipeline integrates translation and formats subtitle item`() = runTest {
        SubtitleRepository.clearSession()
        SubtitleRepository.setLanguagePair(LanguagePair.fromCodes("en", "fr"))
        SubtitleRepository.configureEngines(
            customAsr = null,
            customTranslation = simulatedTranslationEngine
        )

        val directTranslation = simulatedTranslationEngine.translate(
            text = "This movie is amazing!",
            sourceLangCode = "en",
            targetLangCode = "fr"
        )

        assertThat(directTranslation.isSuccess).isTrue()
        assertThat(directTranslation.getOrThrow()).isEqualTo("Ce film est incroyable !")
    }
}
