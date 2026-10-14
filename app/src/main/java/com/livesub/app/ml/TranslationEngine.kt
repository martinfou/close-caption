package com.livesub.app.ml

/**
 * Interface pour le moteur de traduction neuronale on-device.
 */
interface TranslationEngine {
    /**
     * Traduit le texte de [sourceLangCode] vers [targetLangCode].
     */
    suspend fun translate(
        text: String,
        sourceLangCode: String,
        targetLangCode: String
    ): Result<String>

    /**
     * Libère les ressources du traducteur.
     */
    fun close()
}
