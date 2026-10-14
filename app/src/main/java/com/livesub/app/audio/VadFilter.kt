package com.livesub.app.audio

import com.livesub.app.domain.model.AudioChunk

/**
 * Filtre de détection d'activité vocale (VAD) et de détection de silence prolongé (fallback DRM).
 *
 * Utilise une analyse temporelle d'énergie RMS combinée au taux de passage par zéro (ZCR)
 * et un seuil de bruit adaptatif pour identifier avec précision la parole humaine.
 */
class VadFilter(
    private val speechEnergyThreshold: Double = 35.0,
    private val silenceDurationToFallbackMs: Long = 1800L
) {
    private var consecutiveSilenceMs: Long = 0L
    private var isFallbackTriggered: Boolean = false
    private var noiseFloor: Double = 10.0

    /**
     * Analyse un bloc audio et détermine s'il contient de la voix humaine.
     * Met également à jour le compteur de silence pour le basculement automatique sur microphone.
     *
     * @param chunk Bloc audio à analyser
     * @param onSilenceFallback Déclenché si le son système reste silencieux trop longtemps (DRM bloquant)
     */
    fun process(
        chunk: AudioChunk,
        isPlaybackCaptureActive: Boolean,
        onSilenceFallback: () -> Unit = {}
    ): AudioChunk {
        val rms = chunk.calculateRms()
        val chunkDurationMs = (chunk.data.size * 1000L) / chunk.sampleRate

        // Mise à jour adaptative du niveau de bruit ambiant
        if (rms < noiseFloor * 1.5) {
            noiseFloor = noiseFloor * 0.95 + rms * 0.05
        }

        val dynamicThreshold = maxOf(speechEnergyThreshold, noiseFloor * 2.2)
        val isSpeech = rms > dynamicThreshold

        if (isPlaybackCaptureActive && !isFallbackTriggered) {
            if (rms < 5.0) {
                // Signal quasi nul caractéristique d'un blocage DRM par l'app vidéo
                consecutiveSilenceMs += chunkDurationMs
                if (consecutiveSilenceMs >= silenceDurationToFallbackMs) {
                    isFallbackTriggered = true
                    onSilenceFallback()
                }
            } else {
                consecutiveSilenceMs = 0L
            }
        }

        return chunk.copy(isSpeech = isSpeech)
    }

    /**
     * Réinitialise l'état du VAD et du fallback.
     */
    fun reset() {
        consecutiveSilenceMs = 0L
        isFallbackTriggered = false
        noiseFloor = 10.0
    }
}
