package io.github.theswagindisguise.daydeck

import android.app.PendingIntent
import android.content.Intent
import android.service.quicksettings.TileService

/**
 * Quick Settings tile: one tap → open DayDeck straight into the new-task
 * sheet. Requires the tile to be added by the user (Edit QS → add "DayDeck:
 * add task"); holding no state of its own.
 */
class DayDeckTileService : TileService() {
    override fun onClick() {
        super.onClick()
        val intent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_ADD_TASK
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            this,
            2031,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        startActivityAndCollapse(pending)
    }
}
