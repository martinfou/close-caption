package com.livesub.app.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import com.livesub.app.audio.AudioCaptureService
import com.livesub.app.domain.repository.SubtitleRepository
import com.livesub.app.export.SrtExporter
import com.livesub.app.overlay.SubtitleOverlayService

class MainActivity : ComponentActivity() {

    private val hasOverlayState = androidx.compose.runtime.mutableStateOf(false)
    private val hasAudioState = androidx.compose.runtime.mutableStateOf(false)

    private val overlayPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        hasOverlayState.value = checkOverlayPermission()
    }

    private val requestAudioPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        hasAudioState.value = isGranted
        if (!isGranted) {
            Toast.makeText(
                this,
                "L'autorisation audio est nécessaire pour la capture microphone de secours.",
                Toast.LENGTH_LONG
            ).show()
        }
    }

    private val mediaProjectionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            startLiveSubServices(result.resultCode, result.data!!)
        } else {
            Toast.makeText(
                this,
                "Capture audio système annulée. Démarrage en mode microphone de secours.",
                Toast.LENGTH_SHORT
            ).show()
            startLiveSubServices(Activity.RESULT_CANCELED, Intent())
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        hasOverlayState.value = checkOverlayPermission()
        hasAudioState.value = checkAudioPermission()

        setContent {
            val hasOverlay by hasOverlayState
            val hasAudio by hasAudioState

            MainScreen(
                hasOverlayPermission = hasOverlay,
                hasRecordAudioPermission = hasAudio,
                onRequestOverlayPermission = { requestOverlayPermission() },
                onRequestAudioPermission = { requestAudioPermission() },
                onStartService = { startCaptureFlow() },
                onStopService = { stopLiveSubServices() },
                onExportSrt = { handleExportSrt() }
            )
        }
    }

    override fun onResume() {
        super.onResume()
        hasOverlayState.value = checkOverlayPermission()
        hasAudioState.value = checkAudioPermission()
    }

    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun checkAudioPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            overlayPermissionLauncher.launch(intent)
        }
    }

    private fun requestAudioPermission() {
        requestAudioPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
    }

    private fun startCaptureFlow() {
        if (!checkOverlayPermission()) {
            requestOverlayPermission()
            return
        }

        if (!checkAudioPermission()) {
            requestAudioPermission()
            return
        }

        val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjectionLauncher.launch(projectionManager.createScreenCaptureIntent())
    }

    private fun startLiveSubServices(resultCode: Int, data: Intent) {
        // 1. Démarrer le service de capture audio
        val audioIntent = Intent(this, AudioCaptureService::class.java).apply {
            action = AudioCaptureService.ACTION_START
            putExtra(AudioCaptureService.EXTRA_RESULT_CODE, resultCode)
            putExtra(AudioCaptureService.EXTRA_RESULT_DATA, data)
        }
        ContextCompat.startForegroundService(this, audioIntent)

        // 2. Démarrer l'overlay flottant
        val overlayIntent = Intent(this, SubtitleOverlayService::class.java).apply {
            action = SubtitleOverlayService.ACTION_START_OVERLAY
        }
        startService(overlayIntent)

        // 3. Lancer le pipeline ASR -> Traduction
        SubtitleRepository.startPipeline()
    }

    private fun stopLiveSubServices() {
        // 1. Arrêter le pipeline
        SubtitleRepository.stopPipeline()

        // 2. Arrêter le service audio
        val audioIntent = Intent(this, AudioCaptureService::class.java).apply {
            action = AudioCaptureService.ACTION_STOP
        }
        startService(audioIntent)

        // 3. Arrêter le service overlay
        val overlayIntent = Intent(this, SubtitleOverlayService::class.java).apply {
            action = SubtitleOverlayService.ACTION_STOP_OVERLAY
        }
        startService(overlayIntent)
    }

    private fun handleExportSrt() {
        val subtitles = SubtitleRepository.sessionSubtitles
        if (subtitles.isEmpty()) {
            Toast.makeText(this, "Aucun sous-titre à exporter.", Toast.LENGTH_SHORT).show()
            return
        }

        val exportResult = SrtExporter.exportToFile(this, subtitles)
        exportResult.onSuccess { file ->
            Toast.makeText(this, "Export réussi : ${file.name}", Toast.LENGTH_LONG).show()

            try {
                val uri = FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    file
                )
                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_SUBJECT, "Sous-titres LiveSub - ${file.name}")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(shareIntent, "Partager le fichier SRT"))
            } catch (e: Exception) {
                // Si FileProvider n'est pas encore enregistré dans le manifest pour le partage externe direct
                Toast.makeText(this, "Fichier enregistré dans : ${file.absolutePath}", Toast.LENGTH_LONG).show()
            }
        }.onFailure { error ->
            Toast.makeText(this, "Erreur d'exportation : ${error.localizedMessage}", Toast.LENGTH_LONG).show()
        }
    }
}
