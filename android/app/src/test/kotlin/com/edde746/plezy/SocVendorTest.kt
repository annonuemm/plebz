package com.edde746.plezy

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SocVendorTest {
  @Test
  fun androidTwelveNamesTheVendor() {
    // Homatics Box R 4K Plus: ro.soc.manufacturer=Amlogic, ro.hardware=amlogic.
    assertTrue(SocVendor.isAmlogic(socManufacturer = "Amlogic", hardware = "amlogic"))
    assertTrue(SocVendor.isAmlogic(socManufacturer = "Amlogic", hardware = "sabrina"))
  }

  @Test
  fun olderFirmwareFallsBackToTheHardwareName() {
    assertTrue(SocVendor.isAmlogic(socManufacturer = null, hardware = "amlogic"))
    assertTrue(SocVendor.isAmlogic(socManufacturer = "unknown", hardware = "amlogic"))
  }

  @Test
  fun otherVendorsAreNot() {
    assertFalse(SocVendor.isAmlogic(socManufacturer = "Mediatek", hardware = "mt8696"))
    assertFalse(SocVendor.isAmlogic(socManufacturer = null, hardware = "darcy"))
    assertFalse(SocVendor.isAmlogic(socManufacturer = null, hardware = null))
  }
}
