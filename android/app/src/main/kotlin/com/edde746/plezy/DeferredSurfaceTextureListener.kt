package com.edde746.plezy

import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.Looper
import android.view.TextureView

internal class DeferredSurfaceTextureListener(
  private val delegate: TextureView.SurfaceTextureListener,
  private val handler: Handler = Handler(Looper.getMainLooper()),
  private val onSurfaceAvailable: () -> Unit = {},
  private val onSurfaceResized: () -> Unit = {},
  private val isCurrentSurface: (SurfaceTexture) -> Boolean
) : TextureView.SurfaceTextureListener {

  private var pendingResize: Runnable? = null

  // The size the renderer was last given. A landscape/portrait flip against it
  // is a rotation, not a step of a resize animation, so it skips the coalescing
  // delay: until the renderer learns the new size, every frame is drawn for the
  // old one and the view shows it squeezed into the new bounds.
  private var rendererWidth = 0
  private var rendererHeight = 0

  override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
    rendererWidth = width
    rendererHeight = height
    delegate.onSurfaceTextureAvailable(surface, width, height)
    onSurfaceAvailable()
  }

  override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
    pendingResize?.let(handler::removeCallbacks)
    val delay = if (flipsOrientation(width, height)) 0L else RESIZE_DELAY_MILLIS
    pendingResize = Runnable {
      pendingResize = null
      if (isCurrentSurface(surface)) {
        rendererWidth = width
        rendererHeight = height
        delegate.onSurfaceTextureSizeChanged(surface, width, height)
        // The resize only swaps the render target; the frame on screen stays
        // the old-size one until something draws again.
        onSurfaceResized()
      }
    }
    handler.postDelayed(pendingResize!!, delay)
  }

  override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {
    delegate.onSurfaceTextureUpdated(surface)
  }

  override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
    pendingResize?.let(handler::removeCallbacks)
    pendingResize = null
    rendererWidth = 0
    rendererHeight = 0
    return delegate.onSurfaceTextureDestroyed(surface)
  }

  private fun flipsOrientation(width: Int, height: Int): Boolean {
    if (rendererWidth <= 0 || rendererHeight <= 0) return false
    return (width > height) != (rendererWidth > rendererHeight)
  }

  private companion object {
    const val RESIZE_DELAY_MILLIS = 100L
  }
}
