package com.edde746.plezy.shared

import android.view.View
import com.edde746.plezy.R

/**
 * Plebz: where a full-screen video container goes to show its picture in a box behind a hole in
 * the app — the guide's preview on the video plane.
 *
 * The container keeps its full-screen layout, so the picture's fit inside it is unchanged, and is
 * scaled and moved onto the box: a transform, not a layout, so following an animation every frame
 * costs no layout pass. Scaled the same both ways, so the picture keeps its shape. Where the box is
 * not the screen's shape — a phone held upright, whose screen is tall and whose box is 16:9 — the
 * container is scaled until it covers the box and centred on it; the part spilling past the box is
 * behind the app's own page, which covers everything but the hole. Scaled to the box each way on
 * its own, it squeezed the picture into a strip.
 */
internal object PlaneViewport {
  data class Transform(val scale: Float, val translationX: Float, val translationY: Float)

  /** [box] is left, top, right, bottom in window pixels; the container's own frame is [left], [top], [width] × [height]. */
  fun transform(left: Int, top: Int, width: Int, height: Int, box: IntArray): Transform? {
    if (width <= 0 || height <= 0) return null
    val boxWidth = (box[2] - box[0]).toFloat()
    val boxHeight = (box[3] - box[1]).toFloat()
    val scale = maxOf(boxWidth / width, boxHeight / height)
    val centreX = box[0] + boxWidth / 2
    val centreY = box[1] + boxHeight / 2
    return Transform(
      scale = scale,
      translationX = centreX - width * scale / 2 - left,
      translationY = centreY - height * scale / 2 - top
    )
  }

  /**
   * [apply], and again whenever the container is laid out at another size: turning a phone lays
   * the full-screen container out anew after the box was reported, and a transform worked out for
   * the old shape put the picture small in a corner of the band.
   */
  fun follow(container: View, box: () -> IntArray?) {
    box()?.let { apply(container, it) }
    if (container.getTag(R.id.plane_viewport_listener) != null) return
    val listener = View.OnLayoutChangeListener { view, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
      val resized = right - left != oldRight - oldLeft || bottom - top != oldBottom - oldTop
      val moved = left != oldLeft || top != oldTop
      if (resized || moved) box()?.let { apply(view, it) }
    }
    container.addOnLayoutChangeListener(listener)
    container.setTag(R.id.plane_viewport_listener, listener)
  }

  fun apply(container: View, box: IntArray) {
    val transform = transform(container.left, container.top, container.width, container.height, box) ?: return
    container.pivotX = 0f
    container.pivotY = 0f
    container.scaleX = transform.scale
    container.scaleY = transform.scale
    container.translationX = transform.translationX
    container.translationY = transform.translationY
  }
}
