package com.livesub.app.domain.model

/**
 * Bloc audio PCM 16kHz prêt pour le filtrage VAD et l'inférence ASR.
 */
data class AudioChunk(
    val data: ShortArray,
    val sampleRate: Int = 16000,
    val timestampMs: Long = System.currentTimeMillis(),
    val isSpeech: Boolean = false
) {
    /**
     * Convertit les échantillons PCM 16-bit en FloatArray normalisé [-1.0f, 1.0f]
     * requis par les modèles neuronaux (Silero VAD / Sherpa-ONNX).
     */
    fun toFloatArray(): FloatArray {
        val floats = FloatArray(data.size)
        for (i in data.indices) {
            floats[i] = data[i] / 32768.0f
        }
        return floats
    }

    /**
     * Calcule l'énergie RMS (Root Mean Square) du chunk pour estimer le volume sonore.
     */
    fun calculateRms(): Double {
        if (data.isEmpty()) return 0.0
        var sumSquares = 0.0
        for (sample in data) {
            sumSquares += (sample * sample).toDouble()
        }
        return Math.sqrt(sumSquares / data.size)
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as AudioChunk
        return data.contentEquals(other.data) &&
                sampleRate == other.sampleRate &&
                timestampMs == other.timestampMs &&
                isSpeech == other.isSpeech
    }

    override fun hashCode(): Int {
        var result = data.contentHashCode()
        result = 31 * result + sampleRate
        result = 31 * result + timestampMs.hashCode()
        result = 31 * result + isSpeech.hashCode()
        return result
    }
}
