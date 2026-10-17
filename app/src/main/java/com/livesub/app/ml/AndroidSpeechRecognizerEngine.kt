package com.livesub.app.ml

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import com.livesub.app.domain.model.AudioChunk
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import java.io.IOException
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Moteur ASR temps réel continu exploitant le service SpeechRecognizer Android avec watchdog anti-silence.
 * Reconnecte automatiquement les sessions d'écoute en boucle sans interruption.
 */
class AndroidSpeechRecognizerEngine(
    private val context: Context,
    private var sourceLanguage: String = "en-US"
) : AsrEngine {

    companion object {
        private const val TAG = "LiveSub_ASR"
        private const val SILENCE_WATCHDOG_MS = 4000L
    }

    private val _resultFlow = MutableSharedFlow<AsrResult>(
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    override val resultFlow: Flow<AsrResult> = _resultFlow.asSharedFlow()

    private val mainHandler = Handler(Looper.getMainLooper())
    private var speechRecognizer: SpeechRecognizer? = null
    private val isRunning = AtomicBoolean(false)
    private var sessionStartMs = System.currentTimeMillis()
    private var lastEmittedText: String = ""

    // --- Injection de l'audio capturé (AudioPlaybackCapture) dans SpeechRecognizer (API 33+) ---
    @Volatile private var useExternalAudio = false
    private var pipeReadSide: ParcelFileDescriptor? = null // accédé uniquement sur le main thread
    @Volatile private var pipeWriter: OutputStream? = null
    private val audioChannel = Channel<ShortArray>(
        capacity = 50, // ~2s de trames de 40ms
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    private val writerScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val isExternalAudioActive: Boolean
        get() = useExternalAudio && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    private val watchdogRunnable = Runnable {
        if (isRunning.get()) {
            Log.d(TAG, "Watchdog de silence déclenché (4s sans parole) -> renouvellement de la session d'écoute")
            restartSession()
        }
    }

    init {
        mainHandler.post {
            initRecognizer()
        }
        // Écrivain dédié : une écriture bloquante dans le pipe ne doit jamais bloquer la capture audio
        writerScope.launch {
            for (samples in audioChannel) {
                writeToPipe(samples)
            }
        }
    }

    private fun writeToPipe(samples: ShortArray) {
        val out = pipeWriter ?: return
        val buffer = ByteBuffer.allocate(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        buffer.asShortBuffer().put(samples)
        try {
            out.write(buffer.array())
        } catch (e: IOException) {
            // Session terminée côté reconnaisseur (pipe fermé) : on attend la prochaine session
            if (pipeWriter === out) pipeWriter = null
        }
    }

    private fun closePipe() {
        val writer = pipeWriter
        pipeWriter = null
        try { writer?.close() } catch (_: IOException) {}
        try { pipeReadSide?.close() } catch (_: IOException) {}
        pipeReadSide = null
    }

    private fun initRecognizer() {
        try {
            destroyRecognizer()
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context)
            speechRecognizer?.setRecognitionListener(createListener())
            Log.i(TAG, "SpeechRecognizer initialisé avec succès")

            if (isRunning.get()) {
                startListeningInternal()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Erreur lors de l'initialisation du SpeechRecognizer", e)
        }
    }

    private fun resetWatchdog() {
        mainHandler.removeCallbacks(watchdogRunnable)
        if (isRunning.get()) {
            mainHandler.postDelayed(watchdogRunnable, SILENCE_WATCHDOG_MS)
        }
    }

    private fun createListener(): RecognitionListener {
        return object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                Log.d(TAG, "SpeechRecognizer prêt pour la parole (source=${if (isExternalAudioActive) "capture interne" else "micro"})")
                // Le service possède désormais sa propre copie du descripteur : on ferme la nôtre pour que
                // l'écrivain reçoive EPIPE (au lieu de bloquer) quand le service ferme la session.
                try { pipeReadSide?.close() } catch (_: IOException) {}
                pipeReadSide = null
                resetWatchdog()
            }

            override fun onBeginningOfSpeech() {
                Log.d(TAG, "Début de voix détecté")
                sessionStartMs = System.currentTimeMillis()
                resetWatchdog()
            }

            override fun onRmsChanged(rmsdB: Float) {
                // Du son entre dans le micro
                if (rmsdB > 2.0f) {
                    resetWatchdog()
                }
            }

            override fun onBufferReceived(buffer: ByteArray?) {}

            override fun onEndOfSpeech() {
                Log.d(TAG, "Fin de segment vocal")
            }

            override fun onError(error: Int) {
                Log.w(TAG, "SpeechRecognizer onError: code=$error")
                if (isRunning.get()) {
                    val delayMs = when (error) {
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> 300L
                        SpeechRecognizer.ERROR_NO_MATCH,
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> 100L
                        else -> 250L
                    }
                    mainHandler.removeCallbacks(watchdogRunnable)
                    mainHandler.postDelayed({
                        if (isRunning.get()) {
                            restartSession()
                        }
                    }, delayMs)
                }
            }

            override fun onResults(results: Bundle?) {
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val text = matches?.firstOrNull()?.trim().orEmpty()
                val now = System.currentTimeMillis()

                if (text.isNotEmpty() && text != lastEmittedText) {
                    lastEmittedText = text
                    Log.i(TAG, ">>> ASR RÉSULTAT FINAL : \"$text\"")
                    _resultFlow.tryEmit(
                        AsrResult(
                            text = text,
                            isFinal = true,
                            startTimeMs = sessionStartMs,
                            endTimeMs = now
                        )
                    )
                }

                if (isRunning.get()) {
                    mainHandler.post {
                        restartSession()
                    }
                }
            }

            override fun onPartialResults(partialResults: Bundle?) {
                val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val text = matches?.firstOrNull()?.trim().orEmpty()

                if (text.isNotEmpty() && text != lastEmittedText) {
                    Log.d(TAG, ">>> ASR PARTIEL : \"$text\"")
                    resetWatchdog()
                    _resultFlow.tryEmit(
                        AsrResult(
                            text = text,
                            isFinal = false,
                            startTimeMs = sessionStartMs,
                            endTimeMs = System.currentTimeMillis()
                        )
                    )
                }
            }

            override fun onEvent(eventType: Int, params: Bundle?) {}
        }
    }

    private fun restartSession() {
        if (!isRunning.get()) return
        try {
            speechRecognizer?.cancel()
        } catch (e: Exception) {
            Log.w(TAG, "Erreur cancel avant restart", e)
        }
        startListeningInternal()
    }

    private fun startListeningInternal() {
        if (!isRunning.get()) return

        try {
            closePipe()
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, sourceLanguage)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            }

            if (isExternalAudioActive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val (readSide, writeSide) = ParcelFileDescriptor.createPipe()
                pipeReadSide = readSide
                pipeWriter = ParcelFileDescriptor.AutoCloseOutputStream(writeSide)
                intent.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readSide)
                intent.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                intent.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                intent.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, 16000)
            }

            speechRecognizer?.startListening(intent)
            resetWatchdog()
            Log.d(TAG, "Écoute lancée (langue=$sourceLanguage)")
        } catch (e: Exception) {
            Log.e(TAG, "Erreur dans startListeningInternal", e)
            mainHandler.postDelayed({
                if (isRunning.get()) restartSession()
            }, 500L)
        }
    }

    override fun start() {
        isRunning.set(true)
        mainHandler.post {
            startListeningInternal()
        }
    }

    override fun stop() {
        isRunning.set(false)
        mainHandler.removeCallbacks(watchdogRunnable)
        mainHandler.post {
            try {
                speechRecognizer?.stopListening()
                speechRecognizer?.cancel()
            } catch (e: Exception) {
                Log.w(TAG, "Erreur lors de l'arrêt du recognizer", e)
            }
            closePipe()
        }
    }

    override fun setLanguage(langCode: String) {
        val mapped = when (langCode.lowercase()) {
            "en" -> "en-US"
            "fr" -> "fr-FR"
            "es" -> "es-ES"
            "de" -> "de-DE"
            "it" -> "it-IT"
            "ja" -> "ja-JP"
            "ko" -> "ko-KR"
            "pt" -> "pt-BR"
            "zh" -> "zh-CN"
            else -> langCode
        }

        if (sourceLanguage != mapped) {
            sourceLanguage = mapped
            Log.i(TAG, "Nouvelle langue ASR configurée : $sourceLanguage")
            if (isRunning.get()) {
                mainHandler.post {
                    restartSession()
                }
            }
        }
    }

    override fun setExternalAudioEnabled(enabled: Boolean) {
        if (useExternalAudio == enabled) return
        useExternalAudio = enabled
        if (enabled && Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            Log.w(TAG, "Injection audio externe non supportée avant Android 13 : SpeechRecognizer reste sur le micro")
            return
        }
        Log.i(TAG, "Source audio ASR : ${if (enabled) "capture interne (pipe)" else "microphone"}")
        if (isRunning.get()) {
            mainHandler.post { restartSession() }
        }
    }

    override suspend fun feedAudio(chunk: AudioChunk) {
        // En mode micro, SpeechRecognizer capture lui-même le son ; sinon on injecte l'audio interne.
        if (isExternalAudioActive && isRunning.get()) {
            audioChannel.trySend(chunk.data)
        }
    }

    override suspend fun flush() {
        // Géré par SpeechRecognizer lors des transitions de fin d'énoncé.
    }

    override fun reset() {
        lastEmittedText = ""
        sessionStartMs = System.currentTimeMillis()
    }

    private fun destroyRecognizer() {
        try {
            speechRecognizer?.destroy()
        } catch (e: Exception) {
            Log.w(TAG, "Erreur lors de la destruction du SpeechRecognizer", e)
        } finally {
            speechRecognizer = null
        }
    }

    override fun release() {
        stop()
        audioChannel.close()
        writerScope.cancel()
        mainHandler.post {
            destroyRecognizer()
        }
    }
}
