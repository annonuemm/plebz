package com.edde746.plezy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DartHeapPolicyTest {
  private val threshold = 2252L shl 20
  private val gib = 1L shl 30

  private fun select(is64Bit: Boolean, lowRam: Boolean = false, totalMem: Long) =
    DartHeapPolicy.oldGenMegabytes(is64Bit, lowRam, totalMem, threshold)

  @Test
  fun smallBoxesKeepTheTightCap() {
    assertEquals(256, select(is64Bit = false, totalMem = 2 * gib))
    assertEquals(256, select(is64Bit = true, totalMem = 2 * gib))
    assertEquals(256, select(is64Bit = false, lowRam = true, totalMem = 4 * gib))
  }

  @Test
  fun a32BitUserspaceOnFourGigabytesGetsRoom() {
    // Google TV Streamer, Homatics R 4K Plus: 32-bit Android on 4 GB.
    assertEquals(512, select(is64Bit = false, totalMem = 4 * gib - (300L shl 20)))
  }

  @Test
  fun roomy64BitBoxesKeepTheEngineDefault() {
    assertNull(select(is64Bit = true, totalMem = 4 * gib))
  }
}
