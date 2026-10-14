package com.livesub.app.ml

import android.util.LruCache
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Implémentation de la traduction locale via Google ML Kit On-Device Translation.
 * Intègre un cache LRU de 200 entrées pour les expressions récurrentes.
 */
class MlKitTranslationEngine : TranslationEngine {

    private val activeTranslators = mutableMapOf<String, Translator>()
    private val translationCache = LruCache<String, String>(200)

    override suspend fun translate(
        text: String,
        sourceLangCode: String,
        targetLangCode: String
    ): Result<String> = withContext(Dispatchers.IO) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return@withContext Result.success("")
        if (sourceLangCode.equals(targetLangCode, ignoreCase = true)) {
            return@withContext Result.success(trimmed)
        }

        val cacheKey = "$sourceLangCode->$targetLangCode:$trimmed"
        val cached = translationCache.get(cacheKey)
        if (cached != null) {
            return@withContext Result.success(cached)
        }

        try {
            val translator = getOrCreateTranslator(sourceLangCode, targetLangCode)
            val translated = Tasks.await(translator.translate(trimmed))
            translationCache.put(cacheKey, translated)
            Result.success(translated)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private fun getOrCreateTranslator(sourceLang: String, targetLang: String): Translator {
        val key = "$sourceLang-$targetLang"
        return activeTranslators.getOrPut(key) {
            val options = TranslatorOptions.Builder()
                .setSourceLanguage(sourceLang)
                .setTargetLanguage(targetLang)
                .build()
            Translation.getClient(options)
        }
    }

    override fun close() {
        for (translator in activeTranslators.values) {
            translator.close()
        }
        activeTranslators.clear()
        translationCache.evictAll()
    }
}
