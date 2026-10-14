package com.livesub.app.audio

import android.annotation.SuppressLint
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.os.Build
import androidx.annotation.RequiresApi

/**
 * Utilitaire d'initialisation de l'AudioRecord avec AudioPlaybackCapture (Android 10+)
 * ou avec le microphone physique en mode fallback.
 */
object AudioPlaybackCaptureHelper {

    const val SAMPLE_RATE = 16000
    const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
    const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT

    fun calculateMinBufferSize(): Int {
        val minSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        return maxOf(minSize, SAMPLE_RATE * 2) // Au moins 1 seconde de buffer (2 bytes/échantillon)
    }

    /**
     * Crée un AudioRecord capturant l'audio interne numérique généré par les autres apps.
     */
    @RequiresApi(Build.VERSION_CODES.Q)
    @SuppressLint("MissingPermission")
    fun createPlaybackCaptureRecord(
        mediaProjection: MediaProjection,
        bufferSize: Int = calculateMinBufferSize()
    ): AudioRecord {
        val config = AudioPlaybackCaptureConfiguration.Builder(mediaProjection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()

        val audioFormat = AudioFormat.Builder()
            .setEncoding(AUDIO_FORMAT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(CHANNEL_CONFIG)
            .build()

        return AudioRecord.Builder()
            .setAudioFormat(audioFormat)
            .setAudioPlaybackCaptureConfig(config)
            .setBufferSizeInBytes(bufferSize)
            .build()
    }

    /**
     * Crée un AudioRecord standard écoutant via le microphone physique (fallback).
     */
    @SuppressLint("MissingPermission")
    fun createMicrophoneRecord(bufferSize: Int = calculateMinBufferSize()): AudioRecord {
        return AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT,
            bufferSize
        )
    }
}
