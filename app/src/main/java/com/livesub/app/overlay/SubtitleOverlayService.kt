package com.livesub.app.overlay

import android.annotation.SuppressLint
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import androidx.compose.ui.platform.ComposeView
import com.livesub.app.audio.AudioCaptureService
import com.livesub.app.domain.repository.SubtitleRepository
import kotlin.math.max
import kotlin.math.min

/**
 * Service gérant l'overlay flottant au niveau système via WindowManager.
 * Supporte le glisser-déposer sans latence, le redimensionnement et l'adaptation à la rotation de l'écran.
 */
class SubtitleOverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var overlayView: ComposeView? = null
    private val lifecycleOwner = OverlayLifecycleOwner()
    private lateinit var layoutParams: WindowManager.LayoutParams

    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isDragging = false

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        initOverlay()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun initOverlay() {
        val displayMetrics = resources.displayMetrics
        val screenWidth = displayMetrics.widthPixels
        val screenHeight = displayMetrics.heightPixels

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = max(20, (screenWidth - 800) / 2)
            y = 140
        }

        overlayView = ComposeView(this).apply {
            lifecycleOwner.attachToDecor(this)
            lifecycleOwner.onStart()

            setContent {
                SubtitlePill(
                    onCloseClick = {
                        removeOverlay()
                        val stopIntent = Intent(this@SubtitleOverlayService, AudioCaptureService::class.java).apply {
                            action = AudioCaptureService.ACTION_STOP
                        }
                        startService(stopIntent)
                        SubtitleRepository.stopPipeline()
                        stopSelf()
                    },
                    onDrag = { dx, dy ->
                        val displayMetrics = resources.displayMetrics
                        val viewW = overlayView?.width ?: 300
                        val viewH = overlayView?.height ?: 150
                        val maxX = max(0, displayMetrics.widthPixels - viewW)
                        val maxY = max(0, displayMetrics.heightPixels - viewH)

                        val params = this@SubtitleOverlayService.layoutParams
                        params.x = (params.x + dx.toInt()).coerceIn(0, maxX)
                        params.y = (params.y + dy.toInt()).coerceIn(0, maxY)

                        try {
                            if (overlayView?.isAttachedToWindow == true) {
                                windowManager?.updateViewLayout(overlayView, params)
                            }
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                    }
                )
            }
        }

        try {
            windowManager?.addView(overlayView, layoutParams)
        } catch (e: Exception) {
            e.printStackTrace()
            stopSelf()
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        clampOverlayToScreen()
    }

    /**
     * Recentre et s'assure que la fenêtre reste dans les limites visibles lors d'une rotation d'écran.
     */
    private fun clampOverlayToScreen() {
        val metrics = resources.displayMetrics
        val maxX = max(0, metrics.widthPixels - (overlayView?.width ?: 200))
        val maxY = max(0, metrics.heightPixels - (overlayView?.height ?: 100))

        layoutParams.x = layoutParams.x.coerceIn(0, maxX)
        layoutParams.y = layoutParams.y.coerceIn(0, maxY)

        try {
            if (overlayView?.isAttachedToWindow == true) {
                windowManager?.updateViewLayout(overlayView, layoutParams)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP_OVERLAY -> {
                removeOverlay()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun removeOverlay() {
        try {
            overlayView?.let {
                lifecycleOwner.onDestroy()
                if (it.isAttachedToWindow) {
                    windowManager?.removeView(it)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            overlayView = null
        }
    }

    override fun onDestroy() {
        removeOverlay()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_START_OVERLAY = "com.livesub.app.action.START_OVERLAY"
        const val ACTION_STOP_OVERLAY = "com.livesub.app.action.STOP_OVERLAY"
    }
}
