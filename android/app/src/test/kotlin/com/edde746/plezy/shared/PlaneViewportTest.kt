package com.edde746.plezy.shared

import org.junit.Assert.assertEquals
import org.junit.Test

class PlaneViewportTest {
  @Test
  fun aPortraitScreenShowsItsPictureInA169BoxWithoutSqueezingIt() {
    // A phone held upright: the container is the screen, 1080 × 2424; the box
    // is the band across its width, 1080 × 608. A 16:9 picture fills the
    // container's width, so the container is scaled by the width and centred.
    val transform = PlaneViewport.transform(0, 0, 1080, 2424, intArrayOf(0, 300, 1080, 908))!!

    assertEquals(1f, transform.scale, 0.0001f)
    assertEquals(0f, transform.translationX, 0.01f)
    assertEquals(300f + 304f - 1212f, transform.translationY, 0.01f)
  }

  @Test
  fun aTelevisionsBoxOfItsOwnShapeIsScaledOntoItExactly() {
    val transform = PlaneViewport.transform(0, 0, 1920, 1080, intArrayOf(96, 54, 576, 324))!!

    assertEquals(0.25f, transform.scale, 0.0001f)
    assertEquals(96f, transform.translationX, 0.01f)
    assertEquals(54f, transform.translationY, 0.01f)
  }

  @Test
  fun theWholeScreenPutsTheContainerBackAsItWas() {
    val transform = PlaneViewport.transform(0, 0, 1080, 2424, intArrayOf(0, 0, 1080, 2424))!!

    assertEquals(1f, transform.scale, 0.0001f)
    assertEquals(0f, transform.translationX, 0.01f)
    assertEquals(0f, transform.translationY, 0.01f)
  }
}
