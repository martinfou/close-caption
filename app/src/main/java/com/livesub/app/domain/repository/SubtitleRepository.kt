package com.livesub.app.domain.repository

import com.livesub.app.audio.AudioCaptureService
import com.livesub.app.domain.model.LanguagePair
import com.livesub.app.domain.model.SubtitleItem
import com.livesub.app.domain.model.SubtitleUiState
import com.livesub.app.ml.AsrEngine
import com.livesub.app.ml.MockSherpaOnnxAsrEngine
import com.livesub.app.ml.MlKitTranslationEngine
import com.livesub.app.ml.StreamingAsrProcessor
import com.livesub.app.ml.TranslationEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Dépôt central et coordinateur UDF pour le flux de sous-titrage en direct.
 * Fait le pont entre la capture audio, le moteur ASR, la traduction et la couche de présentation.
 */
object SubtitleRepository {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val _uiState = MutableStateFlow(SubtitleUiState())
    val uiState: StateFlow<SubtitleUiState> = _uiState.asStateFlow()

    private val _sessionSubtitles = mutableListOf<SubtitleItem>()
    val sessionSubtitles: List<SubtitleItem>
        @Synchronized get() = _sessionSubtitles.toList()

    private var asrEngine: AsrEngine = MockSherpaOnnxAsrEngine()
    private var translationEngine: TranslationEngine = MlKitTranslationEngine()
    private var streamingProcessor: StreamingAsrProcessor = StreamingAsrProcessor(asrEngine, scope)

    private var audioCollectionJob: Job? = null
    private var asrCollectionJob: Job? = null
    private var serviceSyncJob: Job? = null

    init {
        // Synchroniser l'état du service audio (isRunning, isMicFallback)
        serviceSyncJob = scope.launch {
            AudioCaptureService.serviceState.collect { serviceState ->
                _uiState.value = _uiState.value.copy(
                    isRunning = serviceState.isRunning,
                    isMicFallback = serviceState.isMicFallback
                )
            }
        }
    }

    /**
     * Initialise le pipeline avec des moteurs spécifiques (permet l'injection pour les tests).
     */
    fun configureEngines(
        customAsr: AsrEngine? = null,
        customTranslation: TranslationEngine? = null
    ) {
        customAsr?.let {
            asrEngine = it
            streamingProcessor = StreamingAsrProcessor(asrEngine, scope)
        }
        customTranslation?.let {
            translationEngine = it
        }
    }

    /**
     * Démarre l'écoute du flux audio et la chaîne ASR -> Traduction.
     */
    fun startPipeline() {
        stopPipeline()

        asrCollectionJob = scope.launch {
            // Écouter les phrases finalisées par le processeur ASR
            streamingProcessor.finalizedPhrases.collect { asrResult ->
                val sourceText = asrResult.text.trim()
                if (sourceText.isNotEmpty()) {
                    val currentLang = _uiState.value.activeLanguages
                    val translationResult = translationEngine.translate(
                        text = sourceText,
                        sourceLangCode = currentLang.sourceCode,
                        targetLangCode = currentLang.targetCode
                    )

                    val translatedText = translationResult.getOrDefault(sourceText)

                    val subtitle = SubtitleItem(
                        sourceText = sourceText,
                        translatedText = translatedText,
                        startTimeMs = asrResult.startTimeMs,
                        endTimeMs = asrResult.endTimeMs,
                        isFinal = true
                    )

                    synchronized(_sessionSubtitles) {
                        _sessionSubtitles.add(subtitle)
                    }

                    _uiState.value = _uiState.value.copy(
                        currentSubtitle = subtitle
                    )
                }
            }
        }

        audioCollectionJob = scope.launch {
            // Consommer le flux audio issu de AudioCaptureService
            AudioCaptureService.audioStream.collect { chunk ->
                streamingProcessor.processChunk(chunk)
            }
        }
    }

    /**
     * Stoppe le pipeline de traitement.
     */
    fun stopPipeline() {
        audioCollectionJob?.cancel()
        asrCollectionJob?.cancel()
        audioCollectionJob = null
        asrCollectionJob = null
        streamingProcessor.reset()
    }

    /**
     * Met à jour la paire linguistique active.
     */
    fun setLanguagePair(languages: LanguagePair) {
        _uiState.value = _uiState.value.copy(activeLanguages = languages)
    }

    /**
     * Modifie la taille de la police (en Sp).
     */
    fun setFontSize(sizeSp: Float) {
        val clamped = sizeSp.coerceIn(12f, 32f)
        _uiState.value = _uiState.value.copy(fontSizeSp = clamped)
    }

    /**
     * Modifie l'opacité du fond de l'overlay (0.3f à 1.0f).
     */
    fun setBackgroundOpacity(opacity: Float) {
        val clamped = opacity.coerceIn(0.3f, 1.0f)
        _uiState.value = _uiState.value.copy(backgroundOpacity = clamped)
    }

    /**
     * Bascule le mode réduit / étendu de la pilule flottante.
     */
    fun toggleCollapsed() {
        _uiState.value = _uiState.value.copy(isCollapsed = !_uiState.value.isCollapsed)
    }

    /**
     * Réinitialise l'historique de la session en cours.
     */
    fun clearSession() {
        synchronized(_sessionSubtitles) {
            _sessionSubtitles.clear()
        }
        _uiState.value = _uiState.value.copy(currentSubtitle = null)
    }
}
