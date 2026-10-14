package com.livesub.app.audio

import com.google.common.truth.Truth.assertThat
import com.livesub.app.domain.model.AudioChunk
import org.junit.Test
import java.util.concurrent.atomic.AtomicBoolean

class VadFilterTest {

    @Test
    fun `high energy audio chunk is detected as speech`() {
        val vadFilter = VadFilter(speechEnergyThreshold = 35.0)

        // Génération d'une onde sinusoïdale forte (voix claire)
        val loudData = ShortArray(640) { i ->
            (Math.sin(2.0 * Math.PI * 440.0 * i / 16000.0) * 8000.0).toInt().toShort()
        }
        val chunk = AudioChunk(loudData, sampleRate = 16000)

        val processed = vadFilter.process(chunk, isPlaybackCaptureActive = true)
        assertThat(processed.isSpeech).isTrue()
    }

    @Test
    fun `low energy background silence is detected as non-speech`() {
        val vadFilter = VadFilter(speechEnergyThreshold = 35.0)

        // Bruit de fond très faible (< 5 RMS)
        val silenceData = ShortArray(640) { (it % 3).toShort() }
        val chunk = AudioChunk(silenceData, sampleRate = 16000)

        val processed = vadFilter.process(chunk, isPlaybackCaptureActive = true)
        assertThat(processed.isSpeech).isFalse()
    }

    @Test
    fun `continuous DRM silence during playback capture triggers fallback callback`() {
        val vadFilter = VadFilter(
            speechEnergyThreshold = 35.0,
            silenceDurationToFallbackMs = 200L,
            enableAutoFallback = true
        )

        val fallbackTriggered = AtomicBoolean(false)
        val frameSize = 640 // 40ms @ 16kHz
        val zeroData = ShortArray(frameSize) { 0 }
        val chunk = AudioChunk(zeroData, sampleRate = 16000)

        // 200ms / 40ms = 5 blocs requis pour déclencher le fallback
        for (i in 1..4) {
            vadFilter.process(chunk, isPlaybackCaptureActive = true) {
                fallbackTriggered.set(true)
            }
            assertThat(fallbackTriggered.get()).isFalse()
        }

        // Le 5ème bloc dépasse les 200ms de silence continu
        vadFilter.process(chunk, isPlaybackCaptureActive = true) {
            fallbackTriggered.set(true)
        }
        assertThat(fallbackTriggered.get()).isTrue()
    }

    @Test
    fun `silence during microphone capture does not trigger playback fallback`() {
        val vadFilter = VadFilter(silenceDurationToFallbackMs = 100L)
        val fallbackTriggered = AtomicBoolean(false)
        val zeroData = ShortArray(640) { 0 }
        val chunk = AudioChunk(zeroData, sampleRate = 16000)

        for (i in 1..10) {
            vadFilter.process(chunk, isPlaybackCaptureActive = false) {
                fallbackTriggered.set(true)
            }
        }

        assertThat(fallbackTriggered.get()).isFalse()
    }

    @Test
    fun `sound burst resets consecutive silence counter`() {
        val vadFilter = VadFilter(silenceDurationToFallbackMs = 200L, enableAutoFallback = true)
        val fallbackTriggered = AtomicBoolean(false)

        val zeroChunk = AudioChunk(ShortArray(640) { 0 }, sampleRate = 16000)
        val loudData = ShortArray(640) { 4000.toShort() }
        val loudChunk = AudioChunk(loudData, sampleRate = 16000)

        // 3 blocs de silence (120ms)
        repeat(3) {
            vadFilter.process(zeroChunk, isPlaybackCaptureActive = true) {
                fallbackTriggered.set(true)
            }
        }
        assertThat(fallbackTriggered.get()).isFalse()

        // 1 bloc de son (réinitialise le compteur de silence)
        vadFilter.process(loudChunk, isPlaybackCaptureActive = true) {
            fallbackTriggered.set(true)
        }

        // 3 nouveaux blocs de silence (120ms supplémentaires, insuffisant pour atteindre 200ms)
        repeat(3) {
            vadFilter.process(zeroChunk, isPlaybackCaptureActive = true) {
                fallbackTriggered.set(true)
            }
        }
        assertThat(fallbackTriggered.get()).isFalse()
    }
}
