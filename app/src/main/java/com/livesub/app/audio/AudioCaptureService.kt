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
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.livesub.app.LiveSubApplication
import com.livesub.app.R
import com.livesub.app.domain.model.AudioChunk
import com.livesub.app.domain.model.SubtitleUiState
import com.livesub.app.ui.MainActivity
import kotlinx.coroutines.Dispatchers
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

    override fun onCreate() {
        super.onCreate()
        startForeground(
            LiveSubApplication.NOTIFICATION_ID,
            buildNotification("Initialisation de la capture audio..."),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            } else {
                0
            }
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)

        when (intent?.action) {
            ACTION_START -> {
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
                val resultData = intent.getParcelableExtra<Intent>(EXTRA_RESULT_DATA)

                if (resultCode == Activity.RESULT_OK && resultData != null) {
                    val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    val projection = projectionManager.getMediaProjection(resultCode, resultData)
                    mediaProjection = projection
                    startAudioCapture(projection)
                } else {
                    // Si pas de projection media, démarrage direct sur micro
                    startMicrophoneCapture()
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                audioRecord = AudioPlaybackCaptureHelper.createPlaybackCaptureRecord(projection)
            } else {
                audioRecord = AudioPlaybackCaptureHelper.createMicrophoneRecord()
                isUsingMicrophoneFallback = true
            }

            audioRecord?.startRecording()
            updateServiceState(isRunning = true, isMic = isUsingMicrophoneFallback)
            updateNotification(if (isUsingMicrophoneFallback) "Écoute microphone active" else "Capture audio interne active")

            startReadingLoop(isPlayback = !isUsingMicrophoneFallback)
        } catch (e: Exception) {
            e.printStackTrace()
            // En cas d'échec sur la capture interne, repli sur le micro
            startMicrophoneCapture()
        }
    }

    @SuppressLint("MissingPermission")
    private fun startMicrophoneCapture() {
        stopCurrentRecord()
        isUsingMicrophoneFallback = true
        isRecording.set(true)

        try {
            audioRecord = AudioPlaybackCaptureHelper.createMicrophoneRecord()
            audioRecord?.startRecording()
            updateServiceState(isRunning = true, isMic = true)
            updateNotification("Mode secours : Écoute via microphone physique")

            startReadingLoop(isPlayback = false)
        } catch (e: Exception) {
            e.printStackTrace()
            stopAudioCapture()
        }
    }

    private fun startReadingLoop(isPlayback: Boolean) {
        vadFilter.reset()
        recordingThread = Thread({
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO)

            val frameSize = 640 // 40ms @ 16kHz
            val readBuffer = ShortArray(frameSize)

            while (isRecording.get() && audioRecord?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                val samplesRead = audioRecord?.read(readBuffer, 0, frameSize) ?: 0
                if (samplesRead > 0) {
                    val rawChunk = AudioChunk(readBuffer.copyOf(samplesRead), AudioPlaybackCaptureHelper.SAMPLE_RATE)
                    val processedChunk = vadFilter.process(
                        chunk = rawChunk,
                        isPlaybackCaptureActive = isPlayback,
                        onSilenceFallback = {
                            lifecycleScope.launch(Dispatchers.Main) {
                                // Déclenche la bascule automatique sur micro
                                startMicrophoneCapture()
                            }
                        }
                    )

                    ringBuffer.write(processedChunk.data)

                    // Émission du flux audio vers le moteur d'inférence
                    lifecycleScope.launch(Dispatchers.Default) {
                        _audioStream.emit(processedChunk)
                    }
                }
            }
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
        const val ACTION_START = "com.livesub.app.action.START_CAPTURE"
        const val ACTION_STOP = "com.livesub.app.action.STOP_CAPTURE"
        const val EXTRA_RESULT_CODE = "extra_result_code"
        const val EXTRA_RESULT_DATA = "extra_result_data"

        private val _serviceState = MutableStateFlow(SubtitleUiState())
        val serviceState: StateFlow<SubtitleUiState> = _serviceState.asStateFlow()

        private val _audioStream = MutableSharedFlow<AudioChunk>(extraBufferCapacity = 64)
        val audioStream: SharedFlow<AudioChunk> = _audioStream.asSharedFlow()

        fun updateUiState(transform: (SubtitleUiState) -> SubtitleUiState) {
            _serviceState.value = transform(_serviceState.value)
        }
    }
}
