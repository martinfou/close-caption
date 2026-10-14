package com.livesub.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.livesub.app.domain.model.LanguagePair
import com.livesub.app.domain.model.SubtitleItem
import com.livesub.app.domain.repository.SubtitleRepository

val DarkBackground = Color(0xFF0D0E15)
val CardBackground = Color(0xFF161824)
val CardBorder = Color(0xFF262A3E)
val AccentCyan = Color(0xFF00E5FF)
val AccentGreen = Color(0xFF00E676)
val AccentAmber = Color(0xFFFFAB00)

val AVAILABLE_LANGUAGES = listOf(
    "en" to "Anglais (English)",
    "fr" to "Français (French)",
    "es" to "Espagnol (Spanish)",
    "de" to "Allemand (German)",
    "it" to "Italien (Italian)",
    "pt" to "Portugais (Portuguese)",
    "ja" to "Japonais (Japanese)",
    "zh" to "Chinois (Chinese)"
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    hasOverlayPermission: Boolean,
    hasRecordAudioPermission: Boolean,
    onRequestOverlayPermission: () -> Unit,
    onRequestAudioPermission: () -> Unit,
    onStartService: () -> Unit,
    onStopService: () -> Unit,
    onExportSrt: () -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by SubtitleRepository.uiState.collectAsState()
    val sessionSubtitles = SubtitleRepository.sessionSubtitles

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = "LiveSub",
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                            fontSize = 22.sp
                        )
                        Spacer(modifier = Modifier.width(10.dp))
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .background(AccentCyan.copy(alpha = 0.2f))
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        ) {
                            Text(
                                text = "ON-DEVICE AI",
                                color = AccentCyan,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = DarkBackground)
            )
        },
        containerColor = DarkBackground,
        modifier = modifier
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Section 1 : Carte d'état du service
            item {
                ServiceStatusCard(
                    isRunning = uiState.isRunning,
                    isMicFallback = uiState.isMicFallback,
                    currentSubtitle = uiState.currentSubtitle
                )
            }

            // Section 2 : Permissions requises
            if (!hasOverlayPermission || !hasRecordAudioPermission) {
                item {
                    PermissionsCard(
                        hasOverlayPermission = hasOverlayPermission,
                        hasRecordAudioPermission = hasRecordAudioPermission,
                        onRequestOverlayPermission = onRequestOverlayPermission,
                        onRequestAudioPermission = onRequestAudioPermission
                    )
                }
            }

            // Section 3 : Sélection des langues
            item {
                LanguageSelectionCard(
                    currentPair = uiState.activeLanguages,
                    onPairChanged = { SubtitleRepository.setLanguagePair(it) }
                )
            }

            // Section 4 : Bouton principal d'action
            item {
                MainActionButton(
                    isRunning = uiState.isRunning,
                    canStart = hasOverlayPermission && hasRecordAudioPermission,
                    onStart = onStartService,
                    onStop = onStopService
                )
            }

            // Section 5 : Historique de session & Exportation SRT
            item {
                SessionHistoryHeader(
                    subtitleCount = sessionSubtitles.size,
                    onExportClick = onExportSrt,
                    onClearClick = { SubtitleRepository.clearSession() }
                )
            }

            if (sessionSubtitles.isEmpty()) {
                item {
                    Text(
                        text = "Aucun sous-titre généré pour le moment. Lancez la capture et lisez une vidéo.",
                        color = Color.White.copy(alpha = 0.4f),
                        fontSize = 13.sp,
                        modifier = Modifier.padding(vertical = 12.dp)
                    )
                }
            } else {
                items(sessionSubtitles.takeLast(10).reversed()) { item ->
                    SubtitleHistoryItem(item)
                }
            }

            item {
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

@Composable
fun ServiceStatusCard(
    isRunning: Boolean,
    isMicFallback: Boolean,
    currentSubtitle: SubtitleItem?
) {
    val statusColor by animateColorAsState(
        targetValue = if (isRunning) (if (isMicFallback) AccentAmber else AccentGreen) else Color(0xFF757575),
        label = "statusColor"
    )

    Card(
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = CardBackground),
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, CardBorder, RoundedCornerShape(16.dp))
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .clip(CircleShape)
                            .background(statusColor)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = if (isRunning) {
                            if (isMicFallback) "CAPTURE ACTIVE (SECOURS MICRO)" else "CAPTURE ACTIVE (SON INTERNE)"
                        } else {
                            "SERVICE EN ATTENTE"
                        },
                        color = statusColor,
                        fontWeight = FontWeight.Bold,
                        fontSize = 12.sp,
                        letterSpacing = 0.5.sp
                    )
                }

                Text(
                    text = "Latence < 600ms",
                    color = Color.White.copy(alpha = 0.5f),
                    fontSize = 11.sp
                )
            }

            Spacer(modifier = Modifier.height(10.dp))

            Text(
                text = if (currentSubtitle != null && isRunning) {
                    currentSubtitle.translatedText
                } else if (isRunning) {
                    "Prêt — Détection vocale active (VAD en écoute)..."
                } else {
                    "L'application est prête à transcrire et traduire le son de vos vidéos en temps réel."
                },
                color = if (currentSubtitle != null) Color.White else Color.White.copy(alpha = 0.6f),
                fontSize = 15.sp,
                lineHeight = 20.sp,
                fontWeight = if (currentSubtitle != null) FontWeight.Medium else FontWeight.Normal
            )
        }
    }
}

@Composable
fun PermissionsCard(
    hasOverlayPermission: Boolean,
    hasRecordAudioPermission: Boolean,
    onRequestOverlayPermission: () -> Unit,
    onRequestAudioPermission: () -> Unit
) {
    Card(
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = CardBackground),
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, Color(0xFFFF5252).copy(alpha = 0.4f), RoundedCornerShape(16.dp))
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.Warning,
                    contentDescription = null,
                    tint = Color(0xFFFF5252),
                    modifier = Modifier.size(18.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Autorisations requises",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp
                )
            }

            Spacer(modifier = Modifier.height(10.dp))

            if (!hasOverlayPermission) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "Superposition sur les autres applications",
                        color = Color.White.copy(alpha = 0.8f),
                        fontSize = 13.sp,
                        modifier = Modifier.weight(1f)
                    )
                    Button(
                        onClick = onRequestOverlayPermission,
                        colors = ButtonDefaults.buttonColors(containerColor = AccentCyan),
                        shape = RoundedCornerShape(8.dp)
                    ) {
                        Text("Activer", color = Color.Black, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }

            if (!hasRecordAudioPermission) {
                Spacer(modifier = Modifier.height(8.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "Accès au microphone / enregistrement audio",
                        color = Color.White.copy(alpha = 0.8f),
                        fontSize = 13.sp,
                        modifier = Modifier.weight(1f)
                    )
                    Button(
                        onClick = onRequestAudioPermission,
                        colors = ButtonDefaults.buttonColors(containerColor = AccentCyan),
                        shape = RoundedCornerShape(8.dp)
                    ) {
                        Text("Autoriser", color = Color.Black, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

@Composable
fun LanguageSelectionCard(
    currentPair: LanguagePair,
    onPairChanged: (LanguagePair) -> Unit
) {
    Card(
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = CardBackground),
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, CardBorder, RoundedCornerShape(16.dp))
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Paire linguistique (Traduction)",
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 14.sp
            )

            Spacer(modifier = Modifier.height(12.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                // Langue source
                LanguagePickerBox(
                    label = "Langue audio",
                    currentCode = currentPair.sourceCode,
                    onCodeSelected = { onPairChanged(LanguagePair.fromCodes(it, currentPair.targetCode)) },
                    modifier = Modifier.weight(1f)
                )

                IconButton(
                    onClick = {
                        onPairChanged(
                            LanguagePair(
                                source = currentPair.target,
                                target = currentPair.source
                            )
                        )
                    },
                    modifier = Modifier.padding(horizontal = 4.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Refresh,
                        contentDescription = "Inverser les langues",
                        tint = AccentCyan
                    )
                }

                // Langue cible
                LanguagePickerBox(
                    label = "Langue sous-titres",
                    currentCode = currentPair.targetCode,
                    onCodeSelected = { onPairChanged(LanguagePair.fromCodes(currentPair.sourceCode, it)) },
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
fun LanguagePickerBox(
    label: String,
    currentCode: String,
    onCodeSelected: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    var expanded by remember { mutableStateOf(false) }
    val currentLabel = AVAILABLE_LANGUAGES.find { it.first == currentCode }?.second ?: currentCode

    Column(modifier = modifier) {
        Text(text = label, color = Color.White.copy(alpha = 0.5f), fontSize = 11.sp)
        Spacer(modifier = Modifier.height(4.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .background(Color.Black.copy(alpha = 0.3f))
                .border(1.dp, CardBorder, RoundedCornerShape(10.dp))
                .clickable { expanded = true }
                .padding(horizontal = 10.dp, vertical = 8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = currentLabel.substringBefore(" ("),
                    color = Color.White,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium
                )
                Icon(
                    imageVector = Icons.Default.ArrowDropDown,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.7f),
                    modifier = Modifier.size(18.dp)
                )
            }

            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false },
                modifier = Modifier.background(CardBackground)
            ) {
                AVAILABLE_LANGUAGES.forEach { (code, name) ->
                    DropdownMenuItem(
                        text = { Text(name, color = Color.White, fontSize = 13.sp) },
                        onClick = {
                            onCodeSelected(code)
                            expanded = false
                        }
                    )
                }
            }
        }
    }
}

@Composable
fun MainActionButton(
    isRunning: Boolean,
    canStart: Boolean,
    onStart: () -> Unit,
    onStop: () -> Unit
) {
    if (!isRunning) {
        Button(
            onClick = onStart,
            enabled = canStart,
            colors = ButtonDefaults.buttonColors(
                containerColor = AccentCyan,
                disabledContainerColor = AccentCyan.copy(alpha = 0.3f)
            ),
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp)
        ) {
            Icon(
                imageVector = Icons.Default.PlayArrow,
                contentDescription = null,
                tint = Color.Black
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = "Démarrer le sous-titrage en direct",
                color = Color.Black,
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp
            )
        }
    } else {
        Button(
            onClick = onStop,
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF5252)),
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp)
        ) {
            Text(
                text = "Arrêter le sous-titrage",
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp
            )
        }
    }
}

@Composable
fun SessionHistoryHeader(
    subtitleCount: Int,
    onExportClick: () -> Unit,
    onClearClick: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = "Session en cours ($subtitleCount répliques)",
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = 14.sp
        )

        Row {
            if (subtitleCount > 0) {
                OutlinedButton(
                    onClick = onExportClick,
                    shape = RoundedCornerShape(8.dp),
                    modifier = Modifier.padding(end = 6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Share,
                        contentDescription = null,
                        tint = AccentCyan,
                        modifier = Modifier.size(14.dp)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Export .SRT", color = AccentCyan, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                }

                IconButton(onClick = onClearClick, modifier = Modifier.size(32.dp)) {
                    Icon(
                        imageVector = Icons.Default.Delete,
                        contentDescription = "Effacer session",
                        tint = Color.White.copy(alpha = 0.5f),
                        modifier = Modifier.size(16.dp)
                    )
                }
            }
        }
    }
}

@Composable
fun SubtitleHistoryItem(item: SubtitleItem) {
    Card(
        shape = RoundedCornerShape(10.dp),
        colors = CardDefaults.cardColors(containerColor = CardBackground.copy(alpha = 0.6f)),
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, CardBorder.copy(alpha = 0.5f), RoundedCornerShape(10.dp))
            .padding(vertical = 2.dp)
    ) {
        Column(modifier = Modifier.padding(10.dp)) {
            Text(
                text = SubtitleItem.formatSrtTime(item.startTimeMs) + " → " + SubtitleItem.formatSrtTime(item.endTimeMs),
                color = AccentCyan.copy(alpha = 0.8f),
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = item.translatedText,
                color = Color.White,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium
            )
            if (item.sourceText != item.translatedText) {
                Text(
                    text = item.sourceText,
                    color = Color.White.copy(alpha = 0.45f),
                    fontSize = 11.sp
                )
            }
        }
    }
}
