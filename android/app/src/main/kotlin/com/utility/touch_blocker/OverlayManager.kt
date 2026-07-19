package com.utility.touch_blocker

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageButton

/**
 * OverlayManager — owns the full lifecycle of the native WindowManager overlay.
 *
 * This version uses a **seamless single-bubble UI**:
 *   - No dark backdrop, no text labels, no massive unlock buttons.
 *   - Uses exactly ONE view (idleView containing lockBtn) for both states.
 *   - In IDLE: icon is "ic_lock_open", alpha is 0.6f.
 *   - In LOCKED: icon is "ic_lock" (closed), alpha is 0.3f (highly unobtrusive),
 *     while the root window is expanded to MATCH_PARENT to block all touches on
 *     underlying apps.
 *
 * Layout positioning trick (LOCKED vs IDLE view offsets):
 *   To keep the bubble at the exact same screen position when the window resizes
 *   from WRAP_CONTENT (IDLE) to MATCH_PARENT (LOCKED):
 *   - In LOCKED: Window is MATCH_PARENT, x=0, y=0. We offset the bubble
 *     using view.x = lastIdleX and view.y = lastIdleY.
 *   - In IDLE: Window is WRAP_CONTENT, x=lastIdleX, y=lastIdleY. We reset
 *     view.x = 0f and view.y = 0f (returning it to the window's top-left origin).
 *   - WindowManager.LayoutParams always uses Gravity.TOP or Gravity.START
 *     so the coordinates map 1:1 with screen coordinates.
 *
 * Click vs Drag:
 *   - Tap is gated by a 10px movement threshold.
 *   - In IDLE state, a single tap enters LOCKED state.
 *   - In LOCKED state, entering IDLE (unlocking) requires a **Double Tap**
 *     (within 300ms) on the bubble to prevent accidental unlocks.
 */
class OverlayManager(private val context: Context) {

    enum class OverlayState { IDLE, LOCKED }

    companion object {
        private const val TAG = "OverlayManager"
        private const val VIEW_IDLE = "overlay_idle"
    }

    private fun dpToPx(dp: Int): Int {
        val density = context.resources.displayMetrics.density
        return (dp * density).toInt()
    }

    private val windowManager: WindowManager =
        context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    // Null ↔ overlay is not attached. Single source of truth for isShowing.
    private var overlayRoot: FrameLayout? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var currentState: OverlayState = OverlayState.IDLE

    // Persisted coordinates of the IDLE bubble across states and re-draws.
    // -1 signifies that we need to default to the right side of the screen.
    private var lastIdleX: Int = -1
    private var lastIdleY: Int = dpToPx(120)

    // Direct reference to the bubble button to swap icon drawable and monitor taps.
    private var lockBtn: ImageButton? = null

    // --------------------------------------------------------------------------
    // Public API
    // --------------------------------------------------------------------------

    val isShowing: Boolean get() = overlayRoot != null

    /**
     * Creates the overlay View and attaches it to WindowManager in [OverlayState.IDLE].
     * Idempotent: calling this when already shown is a no-op.
     */
    fun show() {
        if (overlayRoot != null) {
            Log.d(TAG, "show() — overlay already attached, skipping.")
            return
        }
        try {
            // Dynamically default the bubble to the right side of the screen on first show
            if (lastIdleX == -1) {
                val screenWidth = context.resources.displayMetrics.widthPixels
                lastIdleX = screenWidth - dpToPx(16) - dpToPx(45)
            }

            val view = buildOverlayView()
            val params = buildLayoutParams(OverlayState.IDLE)
            windowManager.addView(view, params)
            overlayRoot = view
            overlayParams = params
            currentState = OverlayState.IDLE
            Log.i(TAG, "✅ Overlay attached → IDLE")
        } catch (e: Exception) {
            Log.e(TAG, "show() failed: ${e.message}")
        }
    }

    /**
     * Transitions the live overlay to [newState].
     * Updates both WindowManager layout params (dimensions + flags) and view appearance.
     * No-op if the overlay is not shown or is already in [newState].
     */
    fun updateState(newState: OverlayState) {
        val root = overlayRoot ?: return
        if (currentState == newState) return

        currentState = newState
        try {
            // Apply coordinates translation inside the window, alpha, and icon changes first
            applyStateAppearance(root, newState)
            val params = buildLayoutParams(newState)
            overlayParams = params
            windowManager.updateViewLayout(root, params)
            Log.i(TAG, "Overlay → $newState")
        } catch (e: Exception) {
            Log.e(TAG, "updateState($newState) failed: ${e.message}")
        }
    }

    /**
     * Removes the overlay View completely from WindowManager and nullifies all
     * references. This is the ONLY valid dismiss path.
     *
     * After this call: [isShowing] == false, and all associated RAM is freed.
     * Idempotent: safe to call when already destroyed.
     */
    fun destroy() {
        val root = overlayRoot ?: return
        try {
            windowManager.removeView(root)
            Log.i(TAG, "🗑️ Overlay removed from WindowManager — RAM released.")
        } catch (e: Exception) {
            Log.e(TAG, "destroy() failed: ${e.message}")
        } finally {
            // Null all references to prevent memory leaks
            overlayRoot = null
            overlayParams = null
            lockBtn = null
            currentState = OverlayState.IDLE
        }
    }

    // --------------------------------------------------------------------------
    // View construction — fully programmatic, zero XML binding.
    // --------------------------------------------------------------------------

    /**
     * Builds the overlay root view tree. It contains only a single child: the
     * bubble layout itself. Background is always TRANSPARENT.
     */
    private fun buildOverlayView(): FrameLayout {
        val root = FrameLayout(context).apply {
            setBackgroundColor(Color.TRANSPARENT)
        }
        val buttonSize = dpToPx(45)
        root.addView(
            buildIdleView(),
            FrameLayout.LayoutParams(buttonSize, buttonSize).apply {
                gravity = Gravity.TOP or Gravity.START
            }
        )
        applyStateAppearance(root, OverlayState.IDLE)
        return root
    }

    /**
     * Builds the circular bubble containing the lock/unlock button.
     * Implements ACTION_DOWN, ACTION_MOVE, ACTION_UP touch events to handle
     * drag & drop, and double tap verification.
     */
    private fun buildIdleView(): View = FrameLayout(context).apply {
        tag = VIEW_IDLE

        val padding = dpToPx(10)

        // Coordinates tracked dynamically during drag & drop closure.
        var initialRawX = 0f
        var initialRawY = 0f
        var initialX = 0
        var initialY = 0
        var lastClickTime = 0L

        val btn = ImageButton(context).apply {
            // Initial state is IDLE (unlocked)
            setImageDrawable(getDrawableByName("ic_lock_open"))
            setColorFilter(Color.WHITE)
            contentDescription = "Proteksi Layar"

            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.argb(215, 18, 18, 18)) // ~84% black
            }
            setPadding(padding, padding, padding, padding)
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER

            setOnTouchListener { v, event ->
                val params = overlayParams ?: return@setOnTouchListener false
                when (event.action) {
                    android.view.MotionEvent.ACTION_DOWN -> {
                        initialRawX = event.rawX
                        initialRawY = event.rawY
                        initialX = params.x
                        initialY = params.y
                        true
                    }
                    android.view.MotionEvent.ACTION_MOVE -> {
                        // Only allow dragging when NOT locked
                        if (currentState == OverlayState.IDLE) {
                            val deltaX = event.rawX - initialRawX
                            val deltaY = event.rawY - initialRawY
                            
                            // Gravity.START means deltaX directly adds to initialX (screen coordinates map 1:1)
                            params.x = initialX + deltaX.toInt()
                            params.y = initialY + deltaY.toInt()

                            // Store positions immediately to persist on state changes
                            lastIdleX = params.x
                            lastIdleY = params.y

                            val root = overlayRoot
                            if (root != null) {
                                try {
                                    windowManager.updateViewLayout(root, params)
                                } catch (e: Exception) {
                                    Log.e(TAG, "Failed to update layout: ${e.message}")
                                }
                            }
                        }
                        true
                    }
                    android.view.MotionEvent.ACTION_UP -> {
                        val distance = Math.hypot(
                            (event.rawX - initialRawX).toDouble(),
                            (event.rawY - initialRawY).toDouble()
                        )
                        if (distance < 10.0) {
                            v.performClick()
                            if (currentState == OverlayState.IDLE) {
                                // Single tap to lock screen
                                updateState(OverlayState.LOCKED)
                            } else {
                                // Double tap (within 300ms) to unlock screen
                                val currentTime = System.currentTimeMillis()
                                if (currentTime - lastClickTime < 300) {
                                    updateState(OverlayState.IDLE)
                                } else {
                                    lastClickTime = currentTime
                                }
                            }
                        }
                        true
                    }
                    else -> false
                }
            }
        }

        lockBtn = btn

        addView(
            btn,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
    }

    // --------------------------------------------------------------------------
    // State helpers
    // --------------------------------------------------------------------------

    /**
     * Swaps look and offsets for the bubble based on target state:
     *   - IDLE: Open lock icon, 0.6f opacity, returns bubble to (0,0) window offset.
     *   - LOCKED: Closed lock icon, 0.3f opacity, offsets bubble inside MATCH_PARENT window to (lastIdleX, lastIdleY).
     */
    private fun applyStateAppearance(root: FrameLayout, state: OverlayState) {
        val idleView = root.findViewWithTag<View>(VIEW_IDLE) ?: return
        val btn = lockBtn ?: return

        if (state == OverlayState.IDLE) {
            btn.setImageDrawable(getDrawableByName("ic_lock_open"))
            idleView.alpha = 0.6f
            
            // Return view back to origin since window is repositioned by WindowManager.LayoutParams
            idleView.x = 0f
            idleView.y = 0f
        } else {
            btn.setImageDrawable(getDrawableByName("ic_lock"))
            idleView.alpha = 0.3f
            
            // Explicitly set coordinates inside MATCH_PARENT window so it stays in place
            idleView.x = lastIdleX.toFloat()
            idleView.y = lastIdleY.toFloat()
        }
    }

    /**
     * Builds WindowManager.LayoutParams:
     *   - IDLE: WRAP_CONTENT size at (lastIdleX, lastIdleY). Passes all touches
     *     outside the bubble bounds to underlying applications.
     *   - LOCKED: MATCH_PARENT fullscreen at (0, 0). Blocks all touches across
     *     the entire screen, forcing interactions to hit the bubble view tree.
     */
    private fun buildLayoutParams(state: OverlayState): WindowManager.LayoutParams {
        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_SYSTEM_ALERT

        return when (state) {
            OverlayState.IDLE -> WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                overlayType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = lastIdleX
                y = lastIdleY
            }

            OverlayState.LOCKED -> WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                overlayType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = 0
                y = 0
            }
        }
    }

    /**
     * Safe helper to fetch resource drawables dynamically by name.
     */
    private fun getDrawableByName(name: String): Drawable? {
        val id = context.resources.getIdentifier(name, "drawable", context.packageName)
        return if (id != 0) context.getDrawable(id) else null
    }
}
