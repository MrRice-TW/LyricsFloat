package com.lyricsfloat.lyrics_float

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class OverlayTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        val enabled = MainActivity.activeActivity?.isOverlayVisible() == true
        qsTile?.apply {
            state = if (enabled) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val activity = MainActivity.activeActivity
        if (activity != null) {
            activity.runOnUiThread { activity.toggleOverlayFromTile() }
            return
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_TOGGLE_OVERLAY
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        if (Build.VERSION.SDK_INT >= 34) {
            val pendingIntent = PendingIntent.getActivity(
                this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    companion object {
        fun refresh(context: Context) {
            requestListeningState(context, ComponentName(context, OverlayTileService::class.java))
        }
    }
}
