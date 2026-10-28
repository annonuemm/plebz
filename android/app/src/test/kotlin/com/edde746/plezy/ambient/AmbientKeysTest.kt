package com.edde746.plezy.ambient

import android.view.KeyEvent
import com.edde746.plezy.ambient.AmbientKeys.Effect
import org.junit.Assert.assertEquals
import org.junit.Test

class AmbientKeysTest {
  @Test
  fun okActsOnceReleased() {
    for (key in listOf(KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_BUTTON_A)) {
      assertEquals(Effect.SWALLOW, AmbientKeys.effect(key, down = true))
      assertEquals(Effect.ACT, AmbientKeys.effect(key, down = false))
    }
  }

  @Test
  fun theVolumeGoesOnToTheDevice() {
    for (key in listOf(KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN, KeyEvent.KEYCODE_VOLUME_MUTE)) {
      assertEquals(Effect.PASS, AmbientKeys.effect(key, down = true))
      assertEquals(Effect.PASS, AmbientKeys.effect(key, down = false))
    }
  }

  @Test
  fun anyOtherKeyClosesAsItGoesDown() {
    for (key in listOf(KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)) {
      assertEquals(Effect.CLOSE, AmbientKeys.effect(key, down = true))
      assertEquals(Effect.SWALLOW, AmbientKeys.effect(key, down = false))
    }
  }
}
