package io.github.theswagindisguise.daydeck

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget: shows the open-task count and up to four agenda lines.
 * Data is pushed from Flutter via home_widget (saveWidgetData keys below);
 * the widget only renders what the app last wrote — no network, no account.
 */
class DayDeckWidgetReceiver : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences,
    ) {
        val title = widgetData.getString("open_count", "–") ?: "–"
        val agenda = widgetData.getString("agenda", "open the app to load") ?: "open the app to load"
        val footer = widgetData.getString("footer", "tap to open") ?: "tap to open"

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.daydeck_widget)
            views.setTextViewText(R.id.widget_open_count, "$title open")
            views.setTextViewText(R.id.widget_agenda, agenda)
            views.setTextViewText(R.id.widget_footer, footer)

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                action = MainActivity.ACTION_OPEN_TODAY
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                2030,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.daydeck_widget_root, pendingIntent)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
