package com.edde746.plezy.ambient

import android.app.Activity
import android.view.KeyEvent
import android.view.ViewGroup
import android.view.WindowManager

/**
 * Plebz Ambient in the app's own window ("Bildschirmschoner in Plebz"), for devices that offer no
 * way to choose a screensaver: the same stage as Android's slot, laid over the app when the app
 * says it has seen no input for the viewer's time (`AmbientInApp` on the Dart side keeps that
 * clock). Keys reach it before the app's own handling, through [interceptKey].
 */
internal class AmbientInApp(private val activity: Activity, private val onClosed: () -> Unit) : AmbientStage.Host {
  companion object {
    private const val FADE_IN_MS = 600L
    private const val NIGHT_BRIGHTNESS = 0.1f

    @Volatile private var current: AmbientInApp? = null

    /** Gives a key to the screensaver while it shows; true when it took the key. */
    fun interceptKey(event: KeyEvent): Boolean = current?.intercept(event) ?: false
  }

  private var stage: AmbientStage? = null
  private var closingKey: Int? = null
  private var dimmed = false

  fun attach() {
    current = this
  }

  fun detach() {
    hide()
    setKeepAwake(false)
    if (current === this) current = null
  }

  /** Lays the screensaver over the app; nothing when it already shows. */
  fun show(): Boolean {
    if (stage != null) return true
    if (activity.isFinishing) return false
    val content = activity.findViewById<ViewGroup>(android.R.id.content) ?: return false
    val next = AmbientStage(activity, this)
    next.view.alpha = 0f
    // A pointer (an air mouse) ends it as a key does.
    next.view.setOnClickListener { close() }
    content.addView(next.view, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
    stage = next
    next.start()
    next.view.animate().alpha(1f).setDuration(FADE_IN_MS).start()
    return true
  }

  /** Takes the screensaver away without telling the app, which asked for it. */
  fun hide() {
    val shown = stage ?: return
    stage = null
    shown.stop()
    shown.view.animate().cancel()
    (shown.view.parent as? ViewGroup)?.removeView(shown.view)
    setBright(true)
  }

  /**
   * While on, the device's own screensaver does not start over the app, so this one can, at the
   * viewer's time. A view's flag, not the window's: the player's wakelock owns that one.
   */
  fun setKeepAwake(on: Boolean) {
    activity.window?.decorView?.keepScreenOn = on
  }

  private fun intercept(event: KeyEvent): Boolean {
    val shown = stage
    if (shown == null) {
      // The release of the key that closed the screensaver belongs to it, not to the app.
      if (event.action == KeyEvent.ACTION_UP && event.keyCode == closingKey) {
        closingKey = null
        return true
      }
      return false
    }
    val down = event.action == KeyEvent.ACTION_DOWN
    if (AmbientKeys.effect(event.keyCode, down) == AmbientKeys.Effect.CLOSE) closingKey = event.keyCode
    return shown.onKey(event)
  }

  override fun close() {
    if (stage == null) return
    hide()
    onClosed()
  }

  override fun setBright(bright: Boolean) {
    if (bright == !dimmed) return
    val window = activity.window ?: return
    val params = window.attributes
    params.screenBrightness = if (bright) WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE else NIGHT_BRIGHTNESS
    window.attributes = params
    dimmed = !bright
  }

  // The player is right underneath and in front: it plays on at once.
  override fun resume() = AmbientPlugin.requestResume()
}
