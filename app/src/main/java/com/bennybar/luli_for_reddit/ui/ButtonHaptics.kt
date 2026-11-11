package com.bennybar.luli_for_reddit.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.Window
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.window.DialogWindowProvider
import com.bennybar.luli_for_reddit.app

/**
 * Settings → Button haptics: a key tap when a button, chip, switch or nav-pill
 * tab is tapped, anywhere in the app — sheets and dialogs included.
 *
 * Material 3 components hard-wire their click handling, and there are a few
 * hundred buttons, so rather than touching every call site this watches taps
 * at each window (the activity's, and every Compose dialog / bottom sheet's)
 * and asks the Compose root's semantics tree what is under the finger. Only
 * nodes with a click action and a button-like [Role] count, so tapping a post
 * card, a comment or a link stays silent.
 *
 * Why the window and not the view: AndroidComposeView overrides
 * dispatchTouchEvent without calling super, so a View.OnTouchListener on it
 * never fires. Window.Callback.dispatchTouchEvent sees every touch first.
 * Popups (dropdown menus) are added straight to the WindowManager with no
 * Window, so they stay silent.
 *
 * Intensity matches the draumaz apps (Sustenance, Nickel): the system's
 * VIRTUAL_KEY tap for presses, TOGGLE_ON / TOGGLE_OFF for switches. All go
 * through [View.performHapticFeedback], so the phone's own "Touch feedback"
 * setting still has the last word.
 */
object ButtonHaptics {
    private val ROLES = setOf(Role.Button, Role.Tab, Role.Checkbox, Role.Switch, Role.RadioButton, Role.DropdownList)

    /** Call once, before the first Compose view exists (Application.onCreate). */
    fun install() {
        // onViewCreatedCallback is the compose-test hook for "a Compose root was
        // created"; nothing else in the app uses it, but chain whatever was there.
        val previous = ViewRootForTest.onViewCreatedCallback
        ViewRootForTest.onViewCreatedCallback = { root ->
            previous?.invoke(root)
            root.view.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
                var watcher: TapWatcher? = null
                override fun onViewAttachedToWindow(v: View) {
                    val window = windowOf(v) ?: return
                    val cb = window.callback
                    val w = cb as? TapWatcher ?: TapWatcher(cb).also { window.callback = it }
                    w.roots += root
                    watcher = w
                }
                override fun onViewDetachedFromWindow(v: View) {
                    watcher?.roots?.remove(root)
                    watcher = null
                }
            })
        }
    }

    /** A Compose dialog/sheet's own window (its layout is a DialogWindowProvider), else the activity's. */
    private fun windowOf(v: View): Window? {
        var p = v.parent
        while (p != null) {
            if (p is DialogWindowProvider) return p.window
            p = p.parent
        }
        var c: Context? = v.context
        while (c is ContextWrapper) {
            if (c is Activity) return c.window
            c = c.baseContext
        }
        return null
    }

    /** Sees every touch on its window without consuming it; on a clean tap, plays the haptic for what was tapped. */
    private class TapWatcher(private val inner: Window.Callback) : Window.Callback by inner {
        val roots = mutableListOf<ViewRootForTest>()
        private var downX = 0f
        private var downY = 0f
        private var tap = false

        override fun dispatchTouchEvent(e: MotionEvent): Boolean {
            runCatching { watch(e) }
            return inner.dispatchTouchEvent(e)
        }

        private fun watch(e: MotionEvent) {
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX
                    downY = e.rawY
                    tap = app.settings.value.buttonHaptics && roots.isNotEmpty()
                }
                MotionEvent.ACTION_MOVE -> if (tap) {
                    val slop = ViewConfiguration.get(roots.first().view.context).scaledTouchSlop
                    if (Math.abs(e.rawX - downX) > slop || Math.abs(e.rawY - downY) > slop) tap = false
                }
                MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_CANCEL -> tap = false
                MotionEvent.ACTION_UP -> {
                    // A long press is the button's own business (and usually has its own buzz).
                    if (tap && e.eventTime - e.downTime < ViewConfiguration.getLongPressTimeout()) {
                        // The tap reaches Compose right after this, so state (a switch's) is still the old one.
                        for (root in roots.asReversed()) {
                            val view = root.view
                            val at = IntArray(2).also(view::getLocationOnScreen)
                            val x = e.rawX - at[0]
                            val y = e.rawY - at[1]
                            if (x < 0 || y < 0 || x > view.width || y > view.height) continue
                            feedbackFor(root, x, y)?.let(view::performHapticFeedback)
                            break
                        }
                    }
                    tap = false
                }
            }
        }

        /** The haptic for the topmost clickable under (x, y), or null when it isn't a button. */
        private fun feedbackFor(root: ViewRootForTest, x: Float, y: Float): Int? {
            val node = topmostClickable(root.semanticsOwner.unmergedRootSemanticsNode, Offset(x, y)) ?: return null
            val c = node.config
            if (SemanticsProperties.Disabled in c) return null
            val role = c.getOrNull(SemanticsProperties.Role) ?: return null
            if (role !in ROLES) return null
            val toggle = c.getOrNull(SemanticsProperties.ToggleableState)
            if ((role == Role.Switch || role == Role.Checkbox) && toggle != null && Build.VERSION.SDK_INT >= 34) {
                return if (toggle == ToggleableState.On) HapticFeedbackConstants.TOGGLE_OFF else HapticFeedbackConstants.TOGGLE_ON
            }
            return HapticFeedbackConstants.VIRTUAL_KEY
        }

        /**
         * Pre-order walk keeping the last clickable node whose touch bounds hold
         * the point: later nodes draw on top, and a button inside a clickable
         * card comes after the card, so the button wins.
         */
        private fun topmostClickable(node: SemanticsNode, at: Offset): SemanticsNode? {
            var hit: SemanticsNode? = if (SemanticsActions.OnClick in node.config && node.touchBoundsInRoot.contains(at)) node else null
            for (child in node.children) topmostClickable(child, at)?.let { hit = it }
            return hit
        }
    }
}
