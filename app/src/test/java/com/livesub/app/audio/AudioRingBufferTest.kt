package com.livesub.app.audio

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AudioRingBufferTest {

    @Test
    fun `write and read normal flow preserves exact audio data`() {
        val buffer = AudioRingBuffer(capacity = 100)
        val testData = shortArrayOf(10, 20, 30, 40, 50)

        val written = buffer.write(testData)
        assertThat(written).isEqualTo(5)
        assertThat(buffer.available()).isEqualTo(5)

        val readTarget = ShortArray(5)
        val readCount = buffer.read(readTarget)

        assertThat(readCount).isEqualTo(5)
        assertThat(buffer.available()).isEqualTo(0)
        assertThat(readTarget).isEqualTo(testData)
    }

    @Test
    fun `read requested more than available returns only available samples`() {
        val buffer = AudioRingBuffer(capacity = 50)
        val testData = shortArrayOf(100, 200, 300)
        buffer.write(testData)

        val readTarget = ShortArray(10)
        val readCount = buffer.read(readTarget)

        assertThat(readCount).isEqualTo(3)
        assertThat(readTarget[0]).isEqualTo(100.toShort())
        assertThat(readTarget[1]).isEqualTo(200.toShort())
        assertThat(readTarget[2]).isEqualTo(300.toShort())
        assertThat(buffer.available()).isEqualTo(0)
    }

    @Test
    fun `overflow overwrites oldest samples cleanly`() {
        // Buffer de capacité 5
        val buffer = AudioRingBuffer(capacity = 5)

        // Écriture de 3 échantillons : [1, 2, 3]
        buffer.write(shortArrayOf(1, 2, 3))
        assertThat(buffer.available()).isEqualTo(3)

        // Écriture de 4 échantillons : dépassement de capacité (total écrit 7 > 5)
        // Les échantillons doivent être les 5 derniers : [3, 4, 5, 6, 7]
        buffer.write(shortArrayOf(4, 5, 6, 7))
        assertThat(buffer.available()).isEqualTo(5)

        val dest = ShortArray(5)
        val readCount = buffer.read(dest)

        assertThat(readCount).isEqualTo(5)
        assertThat(dest).isEqualTo(shortArrayOf(3, 4, 5, 6, 7))
    }

    @Test
    fun `clear resets read and write pointers and available count`() {
        val buffer = AudioRingBuffer(capacity = 20)
        buffer.write(shortArrayOf(1, 2, 3, 4))
        assertThat(buffer.available()).isEqualTo(4)

        buffer.clear()
        assertThat(buffer.available()).isEqualTo(0)

        val dest = ShortArray(10)
        val readCount = buffer.read(dest)
        assertThat(readCount).isEqualTo(0)
    }

    @Test
    fun `multiple write-read cycles wrap around circular buffer smoothly`() {
        val buffer = AudioRingBuffer(capacity = 6)

        // Cycle 1 : écrire 4, lire 3 (reste 1)
        buffer.write(shortArrayOf(1, 2, 3, 4))
        val dest1 = ShortArray(3)
        buffer.read(dest1)
        assertThat(dest1).isEqualTo(shortArrayOf(1, 2, 3))
        assertThat(buffer.available()).isEqualTo(1)

        // Cycle 2 : écrire 4 supplémentaires (provoque un wraparound de l'index d'écriture)
        buffer.write(shortArrayOf(5, 6, 7, 8))
        assertThat(buffer.available()).isEqualTo(5)

        // Lire les 5 éléments : l'élément restant [4] suivi de [5, 6, 7, 8]
        val dest2 = ShortArray(5)
        val readCount = buffer.read(dest2)
        assertThat(readCount).isEqualTo(5)
        assertThat(dest2).isEqualTo(shortArrayOf(4, 5, 6, 7, 8))
    }
}
