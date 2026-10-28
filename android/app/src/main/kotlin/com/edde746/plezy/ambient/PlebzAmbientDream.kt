package com.edde746.plezy.ambient

import android.os.Handler
import android.os.Looper
import android.service.dreams.DreamService
import android.view.KeyEvent

/**
 * Plebz Ambient in Android's screensaver slot, where the device lets the viewer choose it (Plebz).
 * The stage ([AmbientStage]) draws; this only hosts it.
 */
class PlebzAmbientDream : DreamService(), AmbientStage.Host {
  private companion object {
    const val RESUME_DELAY_MS = 700L
  }

  private val main = Handler(Looper.getMainLooper())
  private var stage: AmbientStage? = null

  override fun onAttachedToWindow() {
    super.onAttachedToWindow()
    isInteractive = true
    isFullscreen = true
    isScreenBright = true
    val next = AmbientStage(this, this)
    stage = next
    setContentView(next.view)
  }

  override fun onDreamingStarted() {
    super.onDreamingStarted()
    stage?.start()
  }

  override fun onDreamingStopped() {
    stage?.stop()
    super.onDreamingStopped()
  }

  override fun onDetachedFromWindow() {
    stage?.stop()
    super.onDetachedFromWindow()
  }

  override fun dispatchKeyEvent(event: KeyEvent): Boolean = stage?.onKey(event) == true || super.dispatchKeyEvent(event)

  override fun close() = finish()

  override fun setBright(bright: Boolean) {
    isScreenBright = bright
  }

  // The app takes the play only once its screen is back in front.
  override fun resume() {
    main.postDelayed({ AmbientPlugin.requestResume() }, RESUME_DELAY_MS)
  }
}
