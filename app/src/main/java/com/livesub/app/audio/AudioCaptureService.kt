package com.livesub.app.audio

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.livesub.app.LiveSubApplication
import com.livesub.app.R
import com.livesub.app.domain.model.AudioChunk
import com.livesub.app.domain.model.SubtitleUiState
import com.livesub.app.ui.MainActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

class AudioCaptureService : LifecycleService() {

    private var mediaProjection: MediaProjection? = null
    private var audioRecord: AudioRecord? = null
    private val isRecording = AtomicBoolean(false)
    private var recordingThread: Thread? = null

    private val ringBuffer = AudioRingBuffer(AudioPlaybackCaptureHelper.SAMPLE_RATE * 2)
    private val vadFilter = VadFilter()
    private var isUsingMicrophoneFallback = false

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            super.onStop()
            Log.w(TAG, "MediaProjection.onStop() reçu (isRecording=${isRecording.get()})")
            if (isRecording.get()) {
                startMicrophoneCapture("projection arrêtée")
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        val serviceType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        } else {
            0
        }
        startForeground(
            LiveSubApplication.NOTIFICATION_ID,
            buildNotification("Initialisation de la capture audio..."),
            serviceType
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)

        when (intent?.action) {
            ACTION_START -> {
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
                val resultData = intent.getParcelableExtra<Intent>(EXTRA_RESULT_DATA)
                Log.i(TAG, "ACTION_START resultCode=$resultCode hasData=${resultData != null}")

                if (resultCode == Activity.RESULT_OK && resultData != null) {
                    val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    val projection = projectionManager.getMediaProjection(resultCode, resultData)
                    if (projection != null) {
                        mediaProjection = projection
                        startAudioCapture(projection)
                    } else {
                        startMicrophoneCapture("jeton MediaProjection null")
                    }
                } else {
                    // Si pas de projection media, démarrage direct sur micro
                    startMicrophoneCapture("pas de jeton MediaProjection")
                }
            }
            ACTION_STOP -> {
                stopAudioCapture()
                stopSelf()
            }
        }

        return START_NOT_STICKY
    }

    @SuppressLint("MissingPermission")
    private fun startAudioCapture(projection: MediaProjection) {
        if (isRecording.getAndSet(true)) return

        try {
            // Android 14+ exige impérativement d'enregistrer le callback avant d'utiliser la projection
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                projection.registerCallback(projectionCallback, Handler(Looper.getMainLooper()))
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                projection.registerCallback(projectionCallback, null)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                audioRecord = AudioPlaybackCaptureHelper.createPlaybackCaptureRecord(projection)
            } else {
                audioRecord = AudioPlaybackCaptureHelper.createMicrophoneRecord()
                isUsingMicrophoneFallback = true
            }

            audioRecord?.startRecording()
            Log.i(TAG, "AudioRecord démarré (playback=${!isUsingMicrophoneFallback}, state=${audioRecord?.state}, recordingState=${audioRecord?.recordingState})")
            updateServiceState(isRunning = true, isMic = isUsingMicrophoneFallback)
            updateNotification(if (isUsingMicrophoneFallback) "Écoute microphone active" else "Capture audio interne active")

            startReadingLoop(isPlayback = !isUsingMicrophoneFallback)
        } catch (e: Exception) {
            Log.e(TAG, "Échec de la capture audio interne", e)
            // En cas d'échec sur la capture interne, repli sur le micro
            startMicrophoneCapture("exception: ${e.javaClass.simpleName}")
        }
    }

    @SuppressLint("MissingPermission")
    private fun startMicrophoneCapture(reason: String) {
        Log.w(TAG, "Bascule en mode microphone : $reason")
        stopCurrentRecord()
        isUsingMicrophoneFallback = true
        isRecording.set(true)

        updateServiceState(isRunning = true, isMic = true)
        updateNotification("Mode secours : Écoute via microphone du téléphone")
    }

    private fun startReadingLoop(isPlayback: Boolean) {
        vadFilter.reset()
        recordingThread = Thread({
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO)

            val frameSize = 640 // 40ms @ 16kHz
            val readBuffer = ShortArray(frameSize)
            var framesSinceLog = 0
            var maxRms = 0.0

            while (isRecording.get() && audioRecord?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                val samplesRead = audioRecord?.read(readBuffer, 0, frameSize) ?: 0
                if (samplesRead < 0) {
                    Log.e(TAG, "AudioRecord.read() erreur=$samplesRead")
                    Thread.sleep(40)
                }
                if (samplesRead > 0) {
                    val rawChunk = AudioChunk(readBuffer.copyOf(samplesRead), AudioPlaybackCaptureHelper.SAMPLE_RATE)
                    maxRms = maxOf(maxRms, rawChunk.calculateRms())
                    if (++framesSinceLog >= 125) { // ~5s
                        Log.d(TAG, "Capture active : ${framesSinceLog} trames, RMS max=${"%.1f".format(maxRms)}")
                        framesSinceLog = 0
                        maxRms = 0.0
                    }
                    val processedChunk = vadFilter.process(
                        chunk = rawChunk,
                        isPlaybackCaptureActive = isPlayback,
                        onSilenceFallback = {
                            lifecycleScope.launch(Dispatchers.Main) {
                                // Déclenche la bascule automatique sur micro
                                startMicrophoneCapture("silence prolongé (DRM ?)")
                            }
                        }
                    )

                    ringBuffer.write(processedChunk.data)

                    // Émission synchrone et ordonnée du flux audio vers le moteur d'inférence
                    // (une coroutine par trame ne garantissait pas l'ordre des échantillons PCM)
                    _audioStream.tryEmit(processedChunk)
                }
            }
            Log.w(TAG, "Boucle de lecture terminée (isRecording=${isRecording.get()}, recordingState=${audioRecord?.recordingState})")
        }, "LiveSub-AudioReader").apply { start() }
    }

    private fun stopCurrentRecord() {
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            audioRecord = null
        }
    }

    private fun stopAudioCapture() {
        isRecording.set(false)
        recordingThread?.interrupt()
        recordingThread = null
        stopCurrentRecord()

        try {
            mediaProjection?.unregisterCallback(projectionCallback)
            mediaProjection?.stop()
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            mediaProjection = null
        }

        ringBuffer.clear()
        updateServiceState(isRunning = false, isMic = false)
    }

    private fun updateServiceState(isRunning: Boolean, isMic: Boolean) {
        _serviceState.value = _serviceState.value.copy(
            isRunning = isRunning,
            isMicFallback = isMic
        )
    }

    private fun buildNotification(statusText: String): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, LiveSubApplication.NOTIFICATION_CHANNEL_ID)
            .setContentTitle("LiveSub — Sous-titres en direct")
            .setContentText(statusText)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(statusText: String) {
        val notification = buildNotification(statusText)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        manager.notify(LiveSubApplication.NOTIFICATION_ID, notification)
    }

    override fun onDestroy() {
        stopAudioCapture()
        super.onDestroy()
    }

    override fun onBind(intent: Intent): IBinder? {
        super.onBind(intent)
        return null
    }

    companion object {
        private const val TAG = "LiveSub_Audio"
        const val ACTION_START = "com.livesub.app.action.START_CAPTURE"
        const val ACTION_STOP = "com.livesub.app.action.STOP_CAPTURE"
        const val EXTRA_RESULT_CODE = "extra_result_code"
        const val EXTRA_RESULT_DATA = "extra_result_data"

        private val _serviceState = MutableStateFlow(SubtitleUiState())
        val serviceState: StateFlow<SubtitleUiState> = _serviceState.asStateFlow()

        private val _audioStream = MutableSharedFlow<AudioChunk>(
            extraBufferCapacity = 64,
            onBufferOverflow = BufferOverflow.DROP_OLDEST
        )
        val audioStream: SharedFlow<AudioChunk> = _audioStream.asSharedFlow()

        fun updateUiState(transform: (SubtitleUiState) -> SubtitleUiState) {
            _serviceState.value = transform(_serviceState.value)
        }
    }
}
