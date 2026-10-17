package com.livesub.app.overlay

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.livesub.app.domain.repository.SubtitleRepository

/**
 * Composant Jetpack Compose de la pilule flottante de sous-titrage.
 * Offre un design cinématographique, le support du redimensionnement par pincement (pinch-to-zoom),
 * le réglage de l'opacité et l'affichage bilingue fluide.
 */
@Composable
fun SubtitlePill(
    onCloseClick: () -> Unit = {},
    onDrag: (dx: Float, dy: Float) -> Unit = { _, _ -> },
    modifier: Modifier = Modifier
) {
    val uiState by SubtitleRepository.uiState.collectAsState()
    var showSettings by remember { mutableStateOf(false) }

    val pillColor = Color(0xFF121212).copy(alpha = uiState.backgroundOpacity)
    val accentColor = if (uiState.isMicFallback) Color(0xFFFFB74D) else Color(0xFF00E5FF)

    Box(
        modifier = modifier
            .padding(6.dp)
            .fillMaxWidth()
            .pointerInput(Unit) {
                detectTransformGestures { _, _, zoom, _ ->
                    if (kotlin.math.abs(zoom - 1.0f) > 0.05f) {
                        val newSize = uiState.fontSizeSp * zoom
                        SubtitleRepository.setFontSize(newSize)
                    }
                }
            }
    ) {
        Surface(
            shape = RoundedCornerShape(18.dp),
            color = pillColor,
            tonalElevation = 8.dp,
            shadowElevation = 10.dp,
            modifier = Modifier
                .fillMaxWidth()
                .border(
                    width = 1.dp,
                    color = Color.White.copy(alpha = 0.15f),
                    shape = RoundedCornerShape(18.dp)
                )
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Barre supérieure : poignée de glissement interactive
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .pointerInput(Unit) {
                            detectDragGestures { change, dragAmount ->
                                change.consume()
                                onDrag(dragAmount.x, dragAmount.y)
                            }
                        },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    // Badge Source Audio (Interne ou Secours Micro)
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(accentColor.copy(alpha = 0.2f))
                            .padding(horizontal = 8.dp, vertical = 3.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(6.dp)
                                .clip(CircleShape)
                                .background(accentColor)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = if (uiState.isMicFallback) "MIC" else "AUDIO INTERNE",
                            color = accentColor,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 0.5.sp
                        )
                    }

                    // Poignée centrale de déplacement
                    Box(
                        modifier = Modifier
                            .width(52.dp)
                            .height(6.dp)
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.5f))
                    )

                    // Actions rapides (Paramètres, Réduire, Fermer X)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconButton(
                            onClick = { showSettings = !showSettings },
                            modifier = Modifier.size(24.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Default.Settings,
                                contentDescription = "Réglages overlay",
                                tint = Color.White.copy(alpha = 0.7f),
                                modifier = Modifier.size(16.dp)
                            )
                        }
                        Spacer(modifier = Modifier.width(4.dp))
                        IconButton(
                            onClick = { SubtitleRepository.toggleCollapsed() },
                            modifier = Modifier.size(24.dp)
                        ) {
                            Icon(
                                imageVector = if (uiState.isCollapsed) Icons.Default.KeyboardArrowDown else Icons.Default.KeyboardArrowUp,
                                contentDescription = "Réduire",
                                tint = Color.White.copy(alpha = 0.7f),
                                modifier = Modifier.size(18.dp)
                            )
                        }
                        Spacer(modifier = Modifier.width(6.dp))
                        IconButton(
                            onClick = onCloseClick,
                            modifier = Modifier
                                .size(24.dp)
                                .clip(CircleShape)
                                .background(Color(0xFFFF5252).copy(alpha = 0.25f))
                        ) {
                            Icon(
                                imageVector = Icons.Default.Close,
                                contentDescription = "Fermer LiveSub",
                                tint = Color(0xFFFF5252),
                                modifier = Modifier.size(15.dp)
                            )
                        }
                    }
                }

                // Contenu principal : Texte sous-titré
                AnimatedVisibility(
                    visible = !uiState.isCollapsed,
                    enter = fadeIn(),
                    exit = fadeOut()
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        val current = uiState.currentSubtitle
                        if (current != null && current.translatedText.isNotEmpty()) {
                            // Ligne de traduction principale (haute lisibilité)
                            Text(
                                text = current.translatedText,
                                style = TextStyle(
                                    color = Color.White,
                                    fontSize = uiState.fontSizeSp.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    fontFamily = FontFamily.SansSerif,
                                    textAlign = TextAlign.Center,
                                    shadow = Shadow(
                                        color = Color.Black.copy(alpha = 0.9f),
                                        offset = Offset(2f, 2f),
                                        blurRadius = 4f
                                    ),
                                    lineHeight = (uiState.fontSizeSp * 1.3f).sp
                                ),
                                modifier = Modifier.fillMaxWidth()
                            )

                            // Ligne de source optionnelle (texte discret)
                            if (current.sourceText != current.translatedText) {
                                Spacer(modifier = Modifier.height(4.dp))
                                Text(
                                    text = current.sourceText,
                                    style = TextStyle(
                                        color = Color.White.copy(alpha = 0.55f),
                                        fontSize = (uiState.fontSizeSp * 0.75f).sp,
                                        fontFamily = FontFamily.SansSerif,
                                        textAlign = TextAlign.Center
                                    ),
                                    modifier = Modifier.fillMaxWidth()
                                )
                            }
                        } else {
                            // Message d'attente discret
                            Text(
                                text = "En écoute du flux audio...",
                                color = Color.White.copy(alpha = 0.4f),
                                fontSize = 13.sp,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.padding(vertical = 6.dp)
                            )
                        }
                    }
                }

                // Panneau de réglages contextuel (Opacité & Taille)
                AnimatedVisibility(visible = showSettings) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 10.dp)
                            .background(Color.Black.copy(alpha = 0.4f), RoundedCornerShape(12.dp))
                            .padding(10.dp)
                    ) {
                        // Slider taille police
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("Taille texte", color = Color.White, fontSize = 12.sp)
                            Text("${uiState.fontSizeSp.toInt()} sp", color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
                        }
                        Slider(
                            value = uiState.fontSizeSp,
                            onValueChange = { SubtitleRepository.setFontSize(it) },
                            valueRange = 12f..32f,
                            colors = SliderDefaults.colors(
                                thumbColor = accentColor,
                                activeTrackColor = accentColor
                            )
                        )

                        // Slider opacité fond
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("Opacité fond", color = Color.White, fontSize = 12.sp)
                            Text("${(uiState.backgroundOpacity * 100).toInt()}%", color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
                        }
                        Slider(
                            value = uiState.backgroundOpacity,
                            onValueChange = { SubtitleRepository.setBackgroundOpacity(it) },
                            valueRange = 0.3f..1.0f,
                            colors = SliderDefaults.colors(
                                thumbColor = accentColor,
                                activeTrackColor = accentColor
                            )
                        )

                        Spacer(modifier = Modifier.height(4.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.End
                        ) {
                            IconButton(onClick = onCloseClick, modifier = Modifier.size(28.dp)) {
                                Icon(
                                    imageVector = Icons.Default.Close,
                                    contentDescription = "Fermer l'overlay",
                                    tint = Color(0xFFFF5252),
                                    modifier = Modifier.size(18.dp)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
