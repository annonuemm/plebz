package com.edde746.plezy

import android.graphics.SurfaceTexture
import android.os.Looper
import android.view.TextureView
import java.time.Duration
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
class DeferredSurfaceTextureListenerTest {

  private lateinit var surface: SurfaceTexture
  private lateinit var delegate: RecordingListener
  private lateinit var listener: DeferredSurfaceTextureListener
  private var currentSurface: SurfaceTexture? = null
  private var resizedCount = 0

  @Before
  fun setUp() {
    surface = SurfaceTexture(0)
    currentSurface = surface
    delegate = RecordingListener()
    resizedCount = 0
    listener = DeferredSurfaceTextureListener(delegate, onSurfaceResized = { resizedCount++ }) { candidate ->
      candidate === currentSurface
    }
  }

  @After
  fun tearDown() {
    surface.release()
  }

  @Test
  fun forwardsRepeatedSameSizeCallbacks() {
    listener.onSurfaceTextureSizeChanged(surface, 1920, 1080)
    idlePastResizeDelay()
    listener.onSurfaceTextureSizeChanged(surface, 1920, 1080)
    idlePastResizeDelay()

    assertEquals(listOf(1920 to 1080, 1920 to 1080), delegate.sizes)
  }

  @Test
  fun coalescesPendingCallbacksToLatestSize() {
    listener.onSurfaceTextureSizeChanged(surface, 1280, 720)
    listener.onSurfaceTextureSizeChanged(surface, 1920, 1080)
    idlePastResizeDelay()

    assertEquals(listOf(1920 to 1080), delegate.sizes)
  }

  @Test
  fun ignoresCallbackForObsoleteSurface() {
    val replacement = SurfaceTexture(0)
    try {
      listener.onSurfaceTextureSizeChanged(surface, 1920, 1080)
      currentSurface = replacement
      idlePastResizeDelay()

      assertEquals(emptyList<Pair<Int, Int>>(), delegate.sizes)
    } finally {
      replacement.release()
    }
  }

  @Test
  fun destroyingSurfaceCancelsPendingCallback() {
    listener.onSurfaceTextureSizeChanged(surface, 1920, 1080)
    listener.onSurfaceTextureDestroyed(surface)
    idlePastResizeDelay()

    assertEquals(emptyList<Pair<Int, Int>>(), delegate.sizes)
    assertEquals(1, delegate.destroyedCount)
  }

  @Test
  fun forwardsRotationOnNextLoopTurn() {
    listener.onSurfaceTextureAvailable(surface, 2400, 1080)
    listener.onSurfaceTextureSizeChanged(surface, 1080, 2400)

    assertEquals(emptyList<Pair<Int, Int>>(), delegate.sizes)
    shadowOf(Looper.getMainLooper()).idle()

    assertEquals(listOf(1080 to 2400), delegate.sizes)
  }

  @Test
  fun keepsDelayForSameOrientationResize() {
    listener.onSurfaceTextureAvailable(surface, 2400, 1080)
    listener.onSurfaceTextureSizeChanged(surface, 2200, 1080)
    shadowOf(Looper.getMainLooper()).idle()

    assertEquals(emptyList<Pair<Int, Int>>(), delegate.sizes)
    idlePastResizeDelay()
    assertEquals(listOf(2200 to 1080), delegate.sizes)
  }

  @Test
  fun comparesRotationAgainstLastForwardedSize() {
    listener.onSurfaceTextureAvailable(surface, 2400, 1080)
    listener.onSurfaceTextureSizeChanged(surface, 1080, 2400)
    shadowOf(Looper.getMainLooper()).idle()
    listener.onSurfaceTextureSizeChanged(surface, 2400, 1080)
    shadowOf(Looper.getMainLooper()).idle()

    assertEquals(listOf(1080 to 2400, 2400 to 1080), delegate.sizes)
  }

  @Test
  fun reportsEachForwardedResize() {
    listener.onSurfaceTextureSizeChanged(surface, 1280, 720)
    listener.onSurfaceTextureSizeChanged(surface, 1920, 1080)
    idlePastResizeDelay()

    assertEquals(1, resizedCount)
  }

  @Test
  fun skipsResizeReportForObsoleteSurface() {
    val replacement = SurfaceTexture(0)
    try {
      listener.onSurfaceTextureSizeChanged(surface, 1920, 1080)
      currentSurface = replacement
      idlePastResizeDelay()

      assertEquals(0, resizedCount)
    } finally {
      replacement.release()
    }
  }

  private fun idlePastResizeDelay() {
    shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(101))
  }

  private class RecordingListener : TextureView.SurfaceTextureListener {
    val sizes = mutableListOf<Pair<Int, Int>>()
    var destroyedCount = 0

    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) = Unit

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
      sizes += width to height
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit

    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
      destroyedCount++
      return true
    }
  }
}
