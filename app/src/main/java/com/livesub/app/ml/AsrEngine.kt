package com.livesub.app.ml

import com.livesub.app.domain.model.AudioChunk
import kotlinx.coroutines.flow.Flow

/**
 * Résultat intermédiaire ou final de la reconnaissance vocale.
 */
data class AsrResult(
    val text: String,
    val isFinal: Boolean,
    val startTimeMs: Long,
    val endTimeMs: Long
)

/**
 * Contrat pour le moteur de transcription ASR (Sherpa-ONNX, Whisper, etc.)
 */
interface AsrEngine {
    val resultFlow: Flow<AsrResult>

    /**
     * Alimente le moteur avec un bloc audio PCM 16kHz.
     */
    suspend fun feedAudio(chunk: AudioChunk)

    /**
     * Force la finalisation de la phrase courante (ex: après un silence VAD prolongé).
     */
    suspend fun flush()

    /**
     * Réinitialise l'état interne du décodeur.
     */
    fun reset()

    /**
     * Libère les ressources natives.
     */
    fun release()

    /**
     * Démarre la reconnaissance vocale continue.
     */
    fun start() {}

    /**
     * Stoppe la reconnaissance vocale.
     */
    fun stop() {}

    /**
     * Configure la langue source de transcription.
     */
    fun setLanguage(langCode: String) {}

    /**
     * Indique si le moteur doit transcrire l'audio injecté via [feedAudio] (capture interne)
     * plutôt que d'écouter lui-même le microphone.
     */
    fun setExternalAudioEnabled(enabled: Boolean) {}
}
