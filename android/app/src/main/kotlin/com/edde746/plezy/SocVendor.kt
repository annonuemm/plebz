package com.edde746.plezy

import android.os.Build

/**
 * Plebz: whether the device runs on an Amlogic SoC, for defaults that only
 * suit that hardware (mpv's empty letterbox in Dolby Vision; see
 * `MpvPlayerCore.layOutOsdPlane`). Android 12+ names the SoC vendor; before
 * that, Amlogic's reference firmware sets `ro.hardware` to "amlogic".
 */
internal object SocVendor {
  fun isAmlogic(): Boolean = isAmlogic(
    socManufacturer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MANUFACTURER else null,
    hardware = Build.HARDWARE
  )

  fun isAmlogic(socManufacturer: String?, hardware: String?): Boolean =
    socManufacturer?.contains("amlogic", ignoreCase = true) == true ||
      hardware?.contains("amlogic", ignoreCase = true) == true
}
