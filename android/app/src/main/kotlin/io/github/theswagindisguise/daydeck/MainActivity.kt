package io.github.theswagindisguise.daydeck

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Single entry point for every outside nudge into the app:
 *   - ACTION_SEND text/plain  → {type: "share", text: ...}
 *   - quick settings tile      → {type: "add_task"}
 *   - app shortcuts (static)   → {type: "add_task" | "sync_now" | "open_today"}
 *   - home-screen widget tap   → (widget launches MainActivity normally)
 *
 * The Dart side polls via getInitialInput on startup (cold start) and gets
 * subsequent nudges via the setMethodCallHandler stream while running.
 */
class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "daydeck/input"
        const val DEVICE_CAL_CHANNEL = "daydeck/devicecal"
        const val CAL_PERMISSION_REQUEST = 7701
        const val ACTION_ADD_TASK = "io.github.theswagindisguise.daydeck.ADD_TASK"
        const val ACTION_SYNC_NOW = "io.github.theswagindisguise.daydeck.SYNC_NOW"
        const val ACTION_OPEN_TODAY = "io.github.theswagindisguise.daydeck.OPEN_TODAY"

        @Volatile
        private var pendingInput: Map<String, Any?>? = null

        fun consumePendingInput(): Map<String, Any?>? {
            val value = pendingInput
            pendingInput = null
            return value
        }
    }

    private var pendingFromIntent: Map<String, Any?>? = null
    private var calendarPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingFromIntent = inputFromIntent(intent)
        pendingFromIntent?.let { pendingInput = it }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialInput" -> {
                    val input = pendingFromIntent ?: consumePendingInput()
                    pendingFromIntent = null
                    result.success(input)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CAL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkCalendarPermission" -> result.success(hasCalendarPermission())
                "requestCalendarPermission" -> requestCalendarPermission(result)
                "listCalendars" -> queryCalendars(result)
                "listEvents" -> queryEvents(
                    call.argument<Number>("beginMs")?.toLong(),
                    call.argument<Number>("endMs")?.toLong(),
                    result,
                )
                else -> result.notImplemented()
            }
        }
    }

    // ---------------------------------------------------------------
    // Device calendar (read-only). Backs the GOOGLE CALENDAR device
    // toggle: reads what this phone already syncs — including shared
    // calendars the user can't get an iCal secret for. Nothing leaves
    // the device.
    // ---------------------------------------------------------------

    private fun hasCalendarPermission(): Boolean =
        checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED

    private fun requestCalendarPermission(result: MethodChannel.Result) {
        if (hasCalendarPermission()) {
            result.success(true)
            return
        }
        calendarPermissionResult?.success(false) // replace a stale pending request, if any
        calendarPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR), CAL_PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAL_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            calendarPermissionResult?.success(granted)
            calendarPermissionResult = null
        }
    }

    private fun missingPermission(result: MethodChannel.Result): Boolean {
        if (hasCalendarPermission()) return false
        result.error("PERMISSION", "calendar permission not granted", null)
        return true
    }

    private fun queryCalendars(result: MethodChannel.Result) {
        if (missingPermission(result)) return
        try {
            val projection = arrayOf(
                CalendarContract.Calendars._ID,
                CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
                CalendarContract.Calendars.ACCOUNT_NAME,
                CalendarContract.Calendars.CALENDAR_COLOR,
                CalendarContract.Calendars.SYNC_EVENTS,
            )
            val calendars = mutableListOf<Map<String, Any?>>()
            contentResolver.query(
                CalendarContract.Calendars.CONTENT_URI,
                projection,
                null,
                null,
                "${CalendarContract.Calendars.CALENDAR_DISPLAY_NAME} ASC",
            )?.use { cursor ->
                val idIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars._ID)
                val nameIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME)
                val accountIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_NAME)
                val colorIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_COLOR)
                val syncIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.SYNC_EVENTS)
                while (cursor.moveToNext()) {
                    calendars.add(mapOf(
                        "id" to cursor.getLong(idIdx).toString(),
                        "name" to (cursor.getString(nameIdx) ?: "(unnamed calendar)"),
                        "account" to (cursor.getString(accountIdx) ?: ""),
                        "color" to cursor.getInt(colorIdx),
                        "syncEnabled" to (cursor.getInt(syncIdx) == 1),
                    ))
                }
            }
            result.success(calendars)
        } catch (e: SecurityException) {
            result.error("PERMISSION", "calendar permission not granted", null)
        } catch (e: Exception) {
            result.error("CALENDAR", e.message, null)
        }
    }

    private fun queryEvents(beginMs: Long?, endMs: Long?, result: MethodChannel.Result) {
        if (beginMs == null || endMs == null) {
            result.error("ARG", "beginMs and endMs are required", null)
            return
        }
        if (missingPermission(result)) return
        try {
            // Instances.query expands recurrences for us.
            val projection = arrayOf(
                CalendarContract.Instances.EVENT_ID,
                CalendarContract.Instances.CALENDAR_ID,
                CalendarContract.Instances.TITLE,
                CalendarContract.Instances.EVENT_LOCATION,
                CalendarContract.Instances.DESCRIPTION,
                CalendarContract.Instances.BEGIN,
                CalendarContract.Instances.END,
                CalendarContract.Instances.ALL_DAY,
            )
            val events = mutableListOf<Map<String, Any?>>()
            CalendarContract.Instances.query(contentResolver, projection, beginMs, endMs)?.use { cursor ->
                val eventIdx = cursor.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_ID)
                val calIdx = cursor.getColumnIndexOrThrow(CalendarContract.Instances.CALENDAR_ID)
                val titleIdx = cursor.getColumnIndexOrThrow(CalendarContract.Instances.TITLE)
                val locIdx = cursor.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_LOCATION)
                val descIdx = cursor.getColumnIndexOrThrow(CalendarContract.Instances.DESCRIPTION)
                val beginIdx = cursor.getColumnIndexOrThrow(CalendarContract.Instances.BEGIN)
                val endIdx = cursor.getColumnIndexOrThrow(CalendarContract.Instances.END)
                val allDayIdx = cursor.getColumnIndexOrThrow(CalendarContract.Instances.ALL_DAY)
                while (cursor.moveToNext()) {
                    events.add(mapOf(
                        "eventId" to cursor.getLong(eventIdx).toString(),
                        "calendarId" to cursor.getLong(calIdx).toString(),
                        "title" to (cursor.getString(titleIdx) ?: ""),
                        "location" to cursor.getString(locIdx),
                        "notes" to cursor.getString(descIdx),
                        "begin" to cursor.getLong(beginIdx),
                        "end" to cursor.getLong(endIdx),
                        "allDay" to (cursor.getInt(allDayIdx) == 1),
                    ))
                }
            }
            result.success(events)
        } catch (e: SecurityException) {
            result.error("PERMISSION", "calendar permission not granted", null)
        } catch (e: Exception) {
            result.error("CALENDAR", e.message, null)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val input = inputFromIntent(intent)
        pendingInput = input
        flutterEngine?.let { engine ->
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).invokeMethod("nativeInput", input)
        }
    }

    private fun inputFromIntent(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
                if (text.isEmpty()) null else mapOf("type" to "share", "text" to text)
            }
            ACTION_ADD_TASK -> mapOf("type" to "add_task")
            ACTION_SYNC_NOW -> mapOf("type" to "sync_now")
            ACTION_OPEN_TODAY -> mapOf("type" to "open_today")
            else -> null
        }
    }
}
