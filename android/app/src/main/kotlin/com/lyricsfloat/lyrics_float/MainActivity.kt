package com.lyricsfloat.lyrics_float

import android.content.ComponentName
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.MediaMetadata
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var overlayRoot: View? = null
    private var overlayTop: TextView? = null
    private var overlayBottom: TextView? = null
    private var nativeChannel: MethodChannel? = null
    private val overlayWindowManager by lazy { getSystemService(WINDOW_SERVICE) as WindowManager }
    private val overlayPreferences by lazy { getSharedPreferences("lyrics_float_overlay", MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lyrics_float/native")
        nativeChannel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStoragePath" -> result.success(filesDir.absolutePath)
                    "requestMediaAccess" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "hasMediaAccess" -> result.success(hasMediaAccess())
                    "getPlayback" -> result.success(getPlayback(call.argument<String>("sourceMode") ?: "both"))
                    "setOverlay" -> {
                        val enabled = call.argument<Boolean>("enabled") == true
                        if (enabled && !Settings.canDrawOverlays(this)) {
                            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
                            result.success(false)
                        } else {
                            setOverlay(enabled)
                            result.success(enabled)
                        }
                    }
                    "updateOverlay" -> {
                        updateOverlay(
                            call.argument<String>("top") ?: "",
                            call.argument<String>("bottom") ?: "",
                            call.argument<Int>("active") ?: -1
                        )
                        result.success(null)
                    }
                    "setCompact" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
    }

    private fun getPlayback(sourceMode: String): Map<String, Any>? {
        val manager = getSystemService(MEDIA_SESSION_SERVICE) as MediaSessionManager
        val listener = ComponentName(this, LyricsNotificationListener::class.java)
        val sessions = try { manager.getActiveSessions(listener) } catch (_: SecurityException) { return null }
        val allowed = sessions.filter { session ->
            val app = session.packageName.lowercase()
            val spotify = app.contains("spotify")
            val youtube = app.contains("youtube") || app.contains("chrome") ||
                app.contains("firefox") || app.contains("emmx") ||
                app.contains("brave") || app.contains("opera")
            when (sourceMode) {
                "spotify" -> spotify
                "youtube" -> youtube
                else -> spotify || youtube
            }
        }
        val session = allowed.firstOrNull {
            it.playbackState?.state == PlaybackState.STATE_PLAYING && it.metadata != null
        } ?: allowed.firstOrNull { it.metadata != null } ?: return null

        val metadata = session.metadata ?: return null
        val state = session.playbackState
        val title = metadata.getString(MediaMetadata.METADATA_KEY_TITLE) ?: return null
        val artist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""
        val album = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""
        val duration = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION).coerceAtLeast(0)
        var position = state?.position ?: 0L
        if (state?.state == PlaybackState.STATE_PLAYING && state.lastPositionUpdateTime > 0) {
            position += ((SystemClock.elapsedRealtime() - state.lastPositionUpdateTime) * state.playbackSpeed).toLong()
        }
        val source = when {
            session.packageName.contains("spotify") -> "Spotify"
            session.packageName.contains("youtube") -> "YouTube Music"
            else -> session.packageName
        }
        return mapOf(
            "title" to title, "artist" to artist, "album" to album, "source" to source,
            "positionMs" to position.coerceAtLeast(0),
            "durationMs" to duration,
            "isPlaying" to (state?.state == PlaybackState.STATE_PLAYING)
        )
    }

    private fun hasMediaAccess(): Boolean {
        val manager = getSystemService(MEDIA_SESSION_SERVICE) as MediaSessionManager
        val listener = ComponentName(this, LyricsNotificationListener::class.java)
        return try {
            manager.getActiveSessions(listener)
            true
        } catch (_: SecurityException) {
            false
        }
    }

    private fun setOverlay(enabled: Boolean) {
        if (!enabled) {
            overlayRoot?.let { overlayWindowManager.removeView(it) }
            overlayRoot = null
            overlayTop = null
            overlayBottom = null
            return
        }
        if (overlayRoot != null) return
        val width = (resources.displayMetrics.widthPixels - dp(24)).coerceAtLeast(dp(200))
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                setColor(Color.argb(226, 25, 23, 39))
                cornerRadius = dp(14).toFloat()
            }
        }
        val lyrics = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(8), 0, dp(8))
        }
        fun lyricView() = TextView(this).apply {
            textSize = 19f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            setPadding(dp(2), dp(3), dp(2), dp(3))
        }
        val top = lyricView()
        val bottom = lyricView()
        lyrics.addView(top)
        lyrics.addView(bottom)
        root.addView(lyrics, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val close = TextView(this).apply {
            text = "×"
            textSize = 26f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            contentDescription = "關閉歌詞浮窗"
            setOnClickListener {
                setOverlay(false)
                nativeChannel?.invokeMethod("overlayClosed", null)
            }
        }
        root.addView(close, LinearLayout.LayoutParams(dp(44), dp(56)))
        val params = WindowManager.LayoutParams(
            width,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = overlayPreferences.getInt("x", dp(12))
                .coerceIn(0, (resources.displayMetrics.widthPixels - width).coerceAtLeast(0))
            y = overlayPreferences.getInt("y", dp(80))
                .coerceIn(0, (resources.displayMetrics.heightPixels - dp(100)).coerceAtLeast(0))
        }
        val dragListener = object : View.OnTouchListener {
            private var downX = 0f
            private var downY = 0f
            private var startX = 0
            private var startY = 0

            override fun onTouch(view: View, event: MotionEvent): Boolean {
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        downX = event.rawX
                        downY = event.rawY
                        startX = params.x
                        startY = params.y
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        params.x = (startX + (event.rawX - downX).toInt())
                            .coerceIn(0, (resources.displayMetrics.widthPixels - width).coerceAtLeast(0))
                        params.y = (startY + (event.rawY - downY).toInt())
                            .coerceIn(0, (resources.displayMetrics.heightPixels - root.height).coerceAtLeast(0))
                        overlayWindowManager.updateViewLayout(root, params)
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        overlayPreferences.edit().putInt("x", params.x).putInt("y", params.y).apply()
                        return true
                    }
                }
                return false
            }
        }
        lyrics.setOnTouchListener(dragListener)
        top.setOnTouchListener(dragListener)
        bottom.setOnTouchListener(dragListener)
        overlayWindowManager.addView(root, params)
        overlayRoot = root
        overlayTop = top
        overlayBottom = bottom
        updateOverlay("", "", -1)
    }

    private fun updateOverlay(top: String, bottom: String, active: Int) {
        overlayTop?.apply {
            text = top.ifEmpty { "♪" }
            setTextColor(if (active == 0) Color.rgb(255, 216, 91) else Color.LTGRAY)
        }
        overlayBottom?.apply {
            text = bottom
            setTextColor(Color.LTGRAY)
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        setOverlay(false)
        super.onDestroy()
    }
}
