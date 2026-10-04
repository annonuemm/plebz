package com.edde746.plezy

/**
 * The Dart old-generation heap ceiling handed to the engine (fork addition).
 *
 * The 256 MB cap is for genuinely small boxes, where half of physical RAM (the
 * engine's own default) drives low-memory kills (#1349). A 32-bit process on a
 * box with plenty of RAM is not one of them — Amlogic and MediaTek Google TV
 * boxes run a 32-bit userspace on 4 GB — and at 256 MB a long watchlist plus a
 * large guide ran the heap out: seconds of garbage collection with the screen
 * frozen, then the app gone. Those get 512 MB, well inside a 32-bit address
 * space.
 */
internal object DartHeapPolicy {
  const val SMALL_BOX_MEGABYTES = 256
  const val ROOMY_32_BIT_MEGABYTES = 512

  /** Null leaves the engine's default (half of physical RAM), for 64-bit boxes with RAM to spare. */
  fun oldGenMegabytes(is64Bit: Boolean, isLowRamDevice: Boolean, totalMemBytes: Long, lowMemThresholdBytes: Long): Int? {
    if (isLowRamDevice || totalMemBytes <= lowMemThresholdBytes) return SMALL_BOX_MEGABYTES
    if (!is64Bit) return ROOMY_32_BIT_MEGABYTES
    return null
  }
}
