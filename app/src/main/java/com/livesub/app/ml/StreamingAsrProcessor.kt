package com.livesub.app.ml

import com.livesub.app.domain.model.AudioChunk
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch

/**
 * Processeur de flux audio orchestrant l'envoi vers l'ASR et la gestion des frontières de phrases.
 */
class StreamingAsrProcessor(
    private val asrEngine: AsrEngine,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Default)
) {
    private val _finalizedPhrases = MutableSharedFlow<AsrResult>(extraBufferCapacity = 32)
    val finalizedPhrases: SharedFlow<AsrResult> = _finalizedPhrases.asSharedFlow()

    private var speechStartMs: Long = 0L
    private var lastSpeechTimeMs: Long = 0L
    private var silenceCheckJob: Job? = null
    private var isCurrentlySpeaking: Boolean = false

    private var asrCollectorJob: Job? = scope.launch {
        asrEngine.resultFlow.collect { result ->
            if (result.isFinal) {
                _finalizedPhrases.emit(result)
            }
        }
    }

    /**
     * Reçoit un chunk audio traité par le VAD.
     *
     * Tous les chunks (parole ET silence) sont transmis séquentiellement au moteur ASR :
     * un moteur de streaming a besoin du signal continu (y compris les pauses) pour
     * détecter les fins d'énoncé, et l'ordre des échantillons PCM doit être préservé.
     */
    suspend fun processChunk(chunk: AudioChunk) {
        val now = System.currentTimeMillis()

        asrEngine.feedAudio(chunk)

        if (chunk.isSpeech) {
            silenceCheckJob?.cancel()

            if (!isCurrentlySpeaking) {
                isCurrentlySpeaking = true
                speechStartMs = now
            }
            lastSpeechTimeMs = now
        } else if (isCurrentlySpeaking) {
            // Silence détecté après une prise de parole : armer un timer de clôture de phrase
            if (silenceCheckJob?.isActive != true) {
                silenceCheckJob = scope.launch {
                    delay(350L) // 350ms de pause respiratoire = fin de phrase
                    if (isCurrentlySpeaking) {
                        isCurrentlySpeaking = false
                        asrEngine.flush()
                    }
                }
            }
        }
    }

    fun reset() {
        silenceCheckJob?.cancel()
        isCurrentlySpeaking = false
        asrEngine.reset()
    }

    fun release() {
        reset()
        asrCollectorJob?.cancel()
        asrCollectorJob = null
        asrEngine.release()
    }
}
