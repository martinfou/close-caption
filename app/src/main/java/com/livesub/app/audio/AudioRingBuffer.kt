package com.livesub.app.audio

import java.util.concurrent.atomic.AtomicInteger

/**
 * Buffer circulaire thread-safe ultra-rapide pour stocker les échantillons PCM 16kHz
 * sans allouer d'objets sur le tas pendant l'enregistrement audio temps réel.
 *
 * @param capacity Nombre total d'échantillons (ex. 32000 pour 2 secondes d'audio à 16kHz).
 */
class AudioRingBuffer(val capacity: Int = 32000) {

    private val buffer = ShortArray(capacity)
    private var writeHead = 0
    private var readHead = 0
    private val availableSamples = AtomicInteger(0)
    private val lock = Any()

    /**
     * Écrit des échantillons audio dans le buffer circulaire.
     * En cas de dépassement (buffer full), les plus anciens échantillons sont écrasés.
     *
     * @return Le nombre d'échantillons effectivement écrits.
     */
    fun write(data: ShortArray, offset: Int = 0, length: Int = data.size): Int {
        if (length <= 0) return 0
        synchronized(lock) {
            val toWrite = minOf(length, capacity)
            for (i in 0 until toWrite) {
                buffer[writeHead] = data[offset + i]
                writeHead = (writeHead + 1) % capacity
            }

            val currentAvailable = availableSamples.get()
            val newAvailable = minOf(capacity, currentAvailable + toWrite)
            availableSamples.set(newAvailable)

            if (currentAvailable + toWrite > capacity) {
                // Déplacement de la tête de lecture si débordement
                readHead = writeHead
            }
            return toWrite
        }
    }

    /**
     * Lit jusqu'à [length] échantillons dans [dest].
     *
     * @return Le nombre d'échantillons effectivement lus.
     */
    fun read(dest: ShortArray, offset: Int = 0, length: Int = dest.size): Int {
        if (length <= 0) return 0
        synchronized(lock) {
            val toRead = minOf(length, availableSamples.get())
            if (toRead <= 0) return 0

            for (i in 0 until toRead) {
                dest[offset + i] = buffer[readHead]
                readHead = (readHead + 1) % capacity
            }

            availableSamples.addAndGet(-toRead)
            return toRead
        }
    }

    /**
     * Renvoie le nombre d'échantillons actuellement disponibles pour la lecture.
     */
    fun available(): Int = availableSamples.get()

    /**
     * Vide complètement le buffer.
     */
    fun clear() {
        synchronized(lock) {
            writeHead = 0
            readHead = 0
            availableSamples.set(0)
        }
    }
}
