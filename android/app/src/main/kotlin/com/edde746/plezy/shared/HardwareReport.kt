package com.edde746.plezy.shared

import android.app.Activity
import android.content.Context
import android.hardware.display.DisplayManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.view.Display
import com.edde746.plezy.TvDetection
import kotlin.math.roundToInt

/// What this device can actually do, gathered in one pass.
///
/// Every answer here is the device's own, read at the moment it is asked for:
/// which display modes exist, which HDR kinds the panel admits to, which audio
/// formats survive the HDMI route, and which decoders the chip carries. It
/// exists because "does my box do 4K Dolby Vision with Atmos" cannot be
/// answered from a settings screen full of switches — only by asking.
///
/// Nothing here changes anything. Every query is wrapped: a manufacturer's
/// missing implementation costs its own line, never the report.
object HardwareReport {

  private val videoCodecs = listOf(
    "H.264" to MediaFormat.MIMETYPE_VIDEO_AVC,
    "HEVC" to MediaFormat.MIMETYPE_VIDEO_HEVC,
    "AV1" to MediaFormat.MIMETYPE_VIDEO_AV1,
    "VP9" to MediaFormat.MIMETYPE_VIDEO_VP9,
    "Dolby Vision" to MediaFormat.MIMETYPE_VIDEO_DOLBY_VISION,
    "MPEG-2" to MediaFormat.MIMETYPE_VIDEO_MPEG2
  )

  /// Encodings worth asking about, in the order a viewer would recognise them.
  private val audioEncodings: List<Pair<String, Int>> = buildList {
    add("Dolby Digital (AC-3)" to AudioFormat.ENCODING_AC3)
    add("Dolby Digital Plus (E-AC-3)" to AudioFormat.ENCODING_E_AC3)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      add("Dolby Atmos (E-AC-3 JOC)" to AudioFormat.ENCODING_E_AC3_JOC)
      add("Dolby TrueHD" to AudioFormat.ENCODING_DOLBY_TRUEHD)
    }
    add("DTS" to AudioFormat.ENCODING_DTS)
    add("DTS-HD" to AudioFormat.ENCODING_DTS_HD)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      add("DTS:X" to AudioFormat.ENCODING_DTS_UHD_P2)
    }
  }

  fun collect(context: Context, activity: Activity?): Map<String, Any?> = mapOf(
    "device" to device(context),
    "display" to display(context, activity),
    "hdr" to hdr(context, activity),
    "audio" to audio(context),
    "video" to video()
  )

  private fun device(context: Context): Map<String, Any?> = mapOf(
    "manufacturer" to Build.MANUFACTURER,
    "model" to Build.MODEL,
    "androidRelease" to Build.VERSION.RELEASE,
    "sdkInt" to Build.VERSION.SDK_INT,
    "abis" to Build.SUPPORTED_ABIS.toList(),
    "is64Bit" to Build.SUPPORTED_64_BIT_ABIS.isNotEmpty(),
    "isTelevision" to TvDetection.isTv(context)
  )

  private fun currentDisplay(context: Context, activity: Activity?): Display? = runCatching {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      activity?.display
    } else {
      null
    } ?: (context.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager)
      ?.getDisplay(Display.DEFAULT_DISPLAY)
  }.getOrNull()

  private fun display(context: Context, activity: Activity?): Map<String, Any?> {
    val display = currentDisplay(context, activity)
      ?: return mapOf("available" to false)
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      return mapOf("available" to false, "reason" to "Android ${Build.VERSION.RELEASE}")
    }
    val modes = runCatching { display.supportedModes.toList() }.getOrDefault(emptyList())
    val current = runCatching { display.mode }.getOrNull()
    return mapOf(
      "available" to true,
      "current" to current?.let { describeMode(it) },
      "modes" to modes.map { describeMode(it) },
      // One mode means the system decides and an app cannot: a phone, or a
      // stick whose maker locked the output.
      "canSwitch" to (modes.size > 1)
    )
  }

  private fun describeMode(mode: Display.Mode): String =
    "${mode.physicalWidth}x${mode.physicalHeight} @ ${formatRate(mode.refreshRate)} Hz"

  private fun formatRate(rate: Float): String =
    if (kotlin.math.abs(rate - rate.roundToInt()) < 0.01f) "${rate.roundToInt()}" else String.format("%.2f", rate)

  private fun hdr(context: Context, activity: Activity?): Map<String, Any?> {
    val display = currentDisplay(context, activity) ?: return mapOf("types" to emptyList<String>())
    val capabilities = runCatching {
      @Suppress("DEPRECATION")
      display.hdrCapabilities
    }.getOrNull()
    val types = runCatching {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        display.mode.supportedHdrTypes
      } else {
        @Suppress("DEPRECATION")
        capabilities?.supportedHdrTypes ?: IntArray(0)
      }
    }.getOrDefault(IntArray(0))

    return mapOf(
      "types" to types.map { hdrTypeName(it) },
      "maxLuminance" to capabilities?.desiredMaxLuminance?.takeIf { it > 0f },
      "minLuminance" to capabilities?.desiredMinLuminance?.takeIf { it > 0f },
      "wideColorGamut" to runCatching { display.isWideColorGamut }.getOrNull()
    )
  }

  private fun hdrTypeName(type: Int): String = when (type) {
    Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> "Dolby Vision"
    Display.HdrCapabilities.HDR_TYPE_HDR10 -> "HDR10"
    Display.HdrCapabilities.HDR_TYPE_HLG -> "HLG"
    Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS -> "HDR10+"
    else -> "unbekannt ($type)"
  }

  private fun audio(context: Context): Map<String, Any?> {
    val manager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    val formats = audioEncodings.map { (label, encoding) ->
      mapOf("name" to label, "supported" to directPlaybackSupported(encoding))
    }
    return mapOf(
      "formats" to formats,
      "route" to (manager?.let { describeRoute(it) }),
      "maxChannels" to maxChannelCount()
    )
  }

  /// Whether the HDMI route takes this encoding untouched, which is what
  /// "passthrough" means in practice.
  private fun directPlaybackSupported(encoding: Int): Boolean = runCatching {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return false
    @Suppress("DEPRECATION")
    AudioFormat.Builder()
      .setEncoding(encoding)
      .setSampleRate(48000)
      .setChannelMask(AudioFormat.CHANNEL_OUT_5POINT1)
      .build()
      .let { format ->
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
          android.media.AudioTrack.isDirectPlaybackSupported(format, defaultAttributes())
        } else {
          false
        }
      }
  }.getOrDefault(false)

  private fun defaultAttributes() = android.media.AudioAttributes.Builder()
    .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MOVIE)
    .build()

  private fun describeRoute(manager: AudioManager): String? = runCatching {
    val devices = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
    devices.joinToString(", ") { deviceTypeName(it.type) }.ifEmpty { null }
  }.getOrNull()

  private fun deviceTypeName(type: Int): String = when (type) {
    android.media.AudioDeviceInfo.TYPE_HDMI -> "HDMI"
    android.media.AudioDeviceInfo.TYPE_HDMI_ARC -> "HDMI ARC"
    android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Lautsprecher"
    android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth"
    android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
    android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Kopfhörer"
    android.media.AudioDeviceInfo.TYPE_USB_DEVICE, android.media.AudioDeviceInfo.TYPE_USB_HEADSET -> "USB"
    else -> "Typ $type"
  }

  private fun maxChannelCount(): Int? = runCatching {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
    listOf(
      8 to AudioFormat.CHANNEL_OUT_7POINT1_SURROUND,
      6 to AudioFormat.CHANNEL_OUT_5POINT1,
      2 to AudioFormat.CHANNEL_OUT_STEREO
    ).firstOrNull { (_, mask) ->
      android.media.AudioTrack.isDirectPlaybackSupported(
        AudioFormat.Builder()
          .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
          .setSampleRate(48000)
          .setChannelMask(mask)
          .build(),
        defaultAttributes()
      )
    }?.first
  }.getOrNull()

  private fun video(): List<Map<String, Any?>> {
    val codecs = runCatching { MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.toList() }
      .getOrDefault(emptyList())
    return videoCodecs.map { (label, mime) ->
      val info = codecs.firstOrNull { candidate ->
        !candidate.isEncoder &&
          candidate.supportedTypes.any { it.equals(mime, ignoreCase = true) } &&
          MediaCodecQuery.isHardwareAccelerated(candidate)
      }
      mapOf(
        "name" to label,
        "hardware" to (info != null),
        "maxSize" to info?.let { maxSize(it, mime) },
        "tunneling" to info?.let { supportsFeature(it, mime, MediaCodecInfo.CodecCapabilities.FEATURE_TunneledPlayback) },
        "secure" to info?.let { supportsFeature(it, mime, MediaCodecInfo.CodecCapabilities.FEATURE_SecurePlayback) }
      )
    }
  }

  private fun maxSize(info: MediaCodecInfo, mime: String): String? = runCatching {
    val video = info.getCapabilitiesForType(mime).videoCapabilities ?: return null
    "${video.supportedWidths.upper}x${video.supportedHeights.upper}"
  }.getOrNull()

  private fun supportsFeature(info: MediaCodecInfo, mime: String, feature: String): Boolean? = runCatching {
    info.getCapabilitiesForType(mime).isFeatureSupported(feature)
  }.getOrNull()
}
