package com.example.touch_blocker

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.example.touch_blocker/lock_service"

        // SharedPreferences constants — shared with LockAccessibilityService.
        const val PREFS_NAME = "touch_blocker_prefs"
        const val KEY_TARGET_PACKAGES = "target_packages"
        const val KEY_SERVICE_ACTIVE = "service_active"
    }

    // In-memory cache — always kept in sync with SharedPreferences.
    private var targetPackages: Set<String> = emptySet()

    // Tracks whether the lock engine is currently active.
    private var isServiceRunning: Boolean = false

    // Lazy-init prefs reference; available as soon as Activity context is ready.
    private val prefs: SharedPreferences by lazy {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Hydrate in-memory cache from persisted prefs on first engine attach.
        targetPackages = prefs.getStringSet(KEY_TARGET_PACKAGES, emptySet())
            ?: emptySet()
        isServiceRunning = prefs.getBoolean(KEY_SERVICE_ACTIVE, false)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // ----------------------------------------------------------
                    // Service control
                    // ----------------------------------------------------------

                    "setTargetPackages" -> {
                        val packages = call.arguments as? List<*>
                        if (packages == null) {
                            result.error(
                                "INVALID_ARGUMENT",
                                "Expected List<String> of package names",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        val packageList = packages.filterIsInstance<String>()

                        // 1. Update in-memory cache (Set for O(1) lookups).
                        targetPackages = packageList.toHashSet()

                        // 2. Persist to SharedPreferences so state survives
                        //    app kills and service restarts.
                        prefs.edit()
                            .putStringSet(KEY_TARGET_PACKAGES, targetPackages)
                            .apply() // apply() is async — no ANR risk.

                        // 3. Push to live service if already connected.
                        LockAccessibilityService.instance?.setTargetPackages(packageList)

                        result.success(null)
                    }

                    "getTargetPackages" -> {
                        // Read from SharedPreferences; returns List<String> to Flutter.
                        val saved = prefs.getStringSet(KEY_TARGET_PACKAGES, emptySet())
                            ?: emptySet()
                        result.success(saved.toList())
                    }

                    "startLockService" -> {
                        prefs.edit().putBoolean(KEY_SERVICE_ACTIVE, true).apply()
                        if (isServiceRunning) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        LockAccessibilityService.instance?.setTargetPackages(
                            targetPackages.toList()
                        )
                        isServiceRunning = true
                        result.success(null)
                    }

                    "stopLockService" -> {
                        prefs.edit().putBoolean(KEY_SERVICE_ACTIVE, false).apply()
                        if (!isServiceRunning) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        LockAccessibilityService.instance?.setTargetPackages(emptyList())
                        isServiceRunning = false
                        result.success(null)
                    }

                    "isLockServiceActive" -> {
                        result.success(prefs.getBoolean(KEY_SERVICE_ACTIVE, false))
                    }

                    // ----------------------------------------------------------
                    // Permission checks — pure queries, no side effects.
                    // ----------------------------------------------------------

                    "isOverlayGranted" -> {
                        result.success(Settings.canDrawOverlays(this))
                    }

                    "isAccessibilityGranted" -> {
                        result.success(checkAccessibilityGranted())
                    }

                    // ----------------------------------------------------------
                    // Permission requests — open system settings pages.
                    // Flutter re-checks on resume via WidgetsBindingObserver.
                    // ----------------------------------------------------------

                    "requestOverlayPermission" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(null)
                    }

                    "requestAccessibilityPermission" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // --------------------------------------------------------------------------
    // Helpers
    // --------------------------------------------------------------------------

    private fun checkAccessibilityGranted(): Boolean {
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabledServices.contains(packageName, ignoreCase = true)
    }
}
