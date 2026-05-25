package ai.laion.school_bud_e_flutter

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.laion.bude/wakeword"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "bringToForeground" -> {
                    bringAppToForeground()
                    result.success(true)
                }
                "isInForeground" -> {
                    result.success(!isAppInBackground())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isAppInBackground(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val isScreenOn = pm.isInteractive
        if (!isScreenOn) return true
        // Check if our activity is currently resumed (foreground)
        return !hasWindowFocus()
    }

    private fun bringAppToForeground() {
        try {
            // Only act if app is actually in background
            if (!isAppInBackground()) return

            // Wake screen if needed
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isInteractive) {
                @Suppress("DEPRECATION")
                val wl = pm.newWakeLock(
                    PowerManager.FULL_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                    "bude:wakeword"
                )
                wl.acquire(3000L)
            }

            // Dismiss keyguard if needed
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
                val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                km.requestDismissKeyguard(this, null)
            }

            // Bring existing task to front — no new activity, no restart
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            startActivity(intent)
        } catch (e: Exception) {
            // Silently ignore — foreground bring is best-effort
        }
    }
}
