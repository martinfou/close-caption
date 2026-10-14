package com.livesub.app.ml

import com.livesub.app.domain.model.AudioChunk
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Moteur ASR simulant le comportement de Sherpa-ONNX pour les tests et la validation de pipeline.
 */
class MockSherpaOnnxAsrEngine : AsrEngine {

    private val _resultFlow = MutableSharedFlow<AsrResult>(extraBufferCapacity = 16)
    override val resultFlow: Flow<AsrResult> = _resultFlow.asSharedFlow()

    private var accumulatedSamples = 0
    private var sessionStartMs = System.currentTimeMillis()

    override suspend fun feedAudio(chunk: AudioChunk) {
        accumulatedSamples += chunk.data.size

        // Émission d'un résultat intermédiaire simulé
        if (chunk.isSpeech) {
            val now = System.currentTimeMillis()
            _resultFlow.emit(
                AsrResult(
                    text = "Detecting speech...",
                    isFinal = false,
                    startTimeMs = sessionStartMs,
                    endTimeMs = now
                )
            )
        }
    }

    override suspend fun flush() {
        if (accumulatedSamples > 0) {
            val now = System.currentTimeMillis()
            _resultFlow.emit(
                AsrResult(
                    text = "Hello, welcome to this movie scene.",
                    isFinal = true,
                    startTimeMs = sessionStartMs,
                    endTimeMs = now
                )
            )
            accumulatedSamples = 0
            sessionStartMs = now
        }
    }

    override fun reset() {
        accumulatedSamples = 0
        sessionStartMs = System.currentTimeMillis()
    }

    override fun release() {
        reset()
    }
}
