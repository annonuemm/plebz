import 'dart:io' show Platform;

/// mpv's `hwdec` for this platform, as the hardware-decoding setting asks.
///
/// Every player that can be mpv sets it — the full screen, the Live-TV
/// preview and the trailer stage alike (Plebz). Left unset, mpv decodes in
/// software: on a Fire TV Cube (3rd gen) the preview could not keep up and
/// stayed black, and everywhere else it cost the CPU for nothing.
String mpvHwdecValue(bool enabled) {
  if (!enabled) return 'no';

  if (Platform.isMacOS || Platform.isIOS) {
    return 'videotoolbox';
  } else if (Platform.isAndroid) {
    // The fork vo=mediacodec takes MediaCodec decoder buffers straight to the
    // video plane; its query_format accepts IMGFMT_MEDIACODEC and nothing
    // else, so -copy can never draw there and the entry is only ever reached
    // under the GL vos. It stays because it is the only hardware path left
    // below API 26, where the direct AImageReader interop mediacodec needs
    // does not exist (minSdk 25 for Fire OS 6).
    return 'mediacodec,mediacodec-copy';
  } else {
    return 'auto'; // Windows, Linux
  }
}
