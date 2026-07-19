package com.example.touch_blocker

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * LockAccessibilityService — the core background engine of Touch Blocker.
 *
 * Responsibilities:
 *   1. Receive target package Set<String> from MainActivity via [setTargetPackages].
 *   2. Listen to OS window events in a purely event-driven manner (zero polling).
 *   3. Validate foreground package against the in-memory Set for O(1) lookup.
 *   4. Drive [OverlayManager]: show() on target match, destroy() on target leave.
 *
 * Threading model:
 *   - [onAccessibilityEvent] → main thread (OS guarantee).
 *   - [setTargetPackages]    → may arrive on binder thread (from MainActivity).
 *     @Volatile + immutable Set swap ensures safe cross-thread reads.
 *   - [OverlayManager] methods → always called from main thread (via onAccessibilityEvent).
 */
class LockAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "LockA11yService"

        /**
         * Singleton exposed to MainActivity for zero-overhead config push.
         * Nullable — callers must guard against null (service may not be running).
         */
        @Volatile
        var instance: LockAccessibilityService? = null
            private set
    }

    // Immutable Set swap — atomic on JVM reference level; @Volatile ensures visibility.
    @Volatile
    private var targetPackages: Set<String> = emptySet()

    // Deduplication guard: prevents redundant show()/destroy() calls when
    // TYPE_WINDOW_CONTENT_CHANGED fires repeatedly for the same foreground app.
    @Volatile
    private var lastForegroundPackage: String = ""

    // Owns the WindowManager overlay; created once on service connect.
    private var overlayManager: OverlayManager? = null

    // --------------------------------------------------------------------------
    // Lifecycle
    // --------------------------------------------------------------------------

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        overlayManager = OverlayManager(applicationContext)

        // Programmatic config — safety net if XML is mis-scoped.
        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 100L
            flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }

        // Hydrate target packages from SharedPreferences so the service
        // self-recovers after an app kill or device reboot without needing
        // Flutter to re-send the configuration.
        hydrateFromPrefs()

        Log.i(TAG, "✅ Service connected — monitoring ${targetPackages.size} package(s).")
    }

    override fun onDestroy() {
        // Guarantee the overlay is fully removed before the service process dies.
        overlayManager?.destroy()
        overlayManager = null

        instance = null
        targetPackages = emptySet()
        lastForegroundPackage = ""

        Log.i(TAG, "Service destroyed — all references released.")
        super.onDestroy()
    }

    override fun onInterrupt() {
        // OS-level interruption (e.g., incoming call). State is preserved.
        Log.w(TAG, "Service interrupted by system.")
    }

    // --------------------------------------------------------------------------
    // Core event handler
    // NEVER use polling or Timer loops here — event-driven only.
    // --------------------------------------------------------------------------

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return

        // Filter noise: skip our own process and Android system UI.
        if (pkg == packageName || pkg == "com.android.systemui") return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                // Deduplication: only act when the foreground package actually changes.
                // This prevents hammering show()/destroy() on every content repaint.
                if (pkg != lastForegroundPackage) {
                    lastForegroundPackage = pkg
                    handleForegroundChange(pkg)
                }
            }
        }
    }

    // --------------------------------------------------------------------------
    // Core validation + OverlayManager dispatch
    // --------------------------------------------------------------------------

    /**
     * O(1) lookup against [targetPackages] HashSet.
     *
     * Match  → [OverlayManager.show] (idempotent if already visible).
     * No match → [OverlayManager.destroy] (fully removes view from WindowManager).
     */
    private fun handleForegroundChange(currentPackage: String) {
        if (targetPackages.contains(currentPackage)) {
            // Target app is in the foreground — ensure overlay is active.
            Log.d(TAG, "🔒 TARGET: $currentPackage")
            showOverlaySafely()
        } else {
            // Non-target app — ensure overlay is completely gone.
            Log.d(TAG, "🔓 CLEAR:  $currentPackage")
            overlayManager?.destroy()
        }
    }

    private fun showOverlaySafely() {
        val prefs = applicationContext.getSharedPreferences(
            MainActivity.PREFS_NAME,
            Context.MODE_PRIVATE
        )
        val isActive = prefs.getBoolean(MainActivity.KEY_SERVICE_ACTIVE, false)
        if (!isActive) {
            Log.d(TAG, "Overlay skipped: KEY_SERVICE_ACTIVE is false.")
            return
        }

        if (!Settings.canDrawOverlays(this)) {
            Log.w(TAG, "⚠️ SYSTEM_ALERT_WINDOW not granted — overlay skipped.")
            return
        }
        overlayManager?.show()
    }

    // --------------------------------------------------------------------------
    // Public API — called by MainActivity via singleton reference.
    // --------------------------------------------------------------------------

    /**
     * Atomically replaces the monitored package list.
     * Thread-safe via @Volatile + immutable Set swap.
     */
    fun setTargetPackages(packages: List<String>) {
        targetPackages = packages.toHashSet()
        Log.i(TAG, "Target packages updated (${targetPackages.size}): $targetPackages")
    }

    // --------------------------------------------------------------------------
    // Private helpers
    // --------------------------------------------------------------------------

    /**
     * Reads persisted package list from SharedPreferences and loads it into
     * [targetPackages]. Called once in [onServiceConnected] to self-recover
     * state without requiring Flutter to be open or active.
     *
     * Uses the same PREFS_NAME / KEY_TARGET_PACKAGES constants as [MainActivity]
     * to ensure both components read from the same storage slot.
     */
    private fun hydrateFromPrefs() {
        val prefs = applicationContext.getSharedPreferences(
            MainActivity.PREFS_NAME,
            Context.MODE_PRIVATE
        )
        val saved = prefs.getStringSet(MainActivity.KEY_TARGET_PACKAGES, emptySet())
            ?: emptySet()
        if (saved.isNotEmpty()) {
            targetPackages = saved
            Log.i(TAG, "Hydrated from prefs — ${targetPackages.size} package(s): $targetPackages")
        }
    }
}
