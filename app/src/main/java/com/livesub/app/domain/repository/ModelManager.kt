package com.livesub.app.domain.repository

import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateRemoteModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Gestionnaire des modèles de traduction hors-ligne ML Kit.
 */
class ModelManager {

    private val modelManager = RemoteModelManager.getInstance()

    /**
     * Vérifie si un pack de langue spécifique est déjà téléchargé sur l'appareil.
     */
    suspend fun isModelDownloaded(languageCode: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val model = TranslateRemoteModel.Builder(languageCode).build()
            Tasks.await(modelManager.isModelDownloaded(model))
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Télécharge un pack de langue pour utilisation hors-ligne.
     */
    suspend fun downloadModel(languageCode: String, wifiOnly: Boolean = false): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            val model = TranslateRemoteModel.Builder(languageCode).build()
            val conditionsBuilder = DownloadConditions.Builder()
            if (wifiOnly) {
                conditionsBuilder.requireWifi()
            }
            Tasks.await(modelManager.download(model, conditionsBuilder.build()))
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Supprime un pack de langue pour libérer de l'espace disque.
     */
    suspend fun deleteModel(languageCode: String): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            val model = TranslateRemoteModel.Builder(languageCode).build()
            Tasks.await(modelManager.deleteDownloadedModel(model))
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
