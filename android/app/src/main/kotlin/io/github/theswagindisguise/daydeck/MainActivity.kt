package io.github.theswagindisguise.daydeck

import android.content.Intent
import android.os.Bundle
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
