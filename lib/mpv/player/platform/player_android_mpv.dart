import 'package:flutter/foundation.dart';

import '../../../utils/app_logger.dart';
import '../player_native.dart';
import '../video_rect_support.dart';

/// Android's mpv backend, with the one arrangement a surface cannot provide:
/// a picture *inside* the widget tree.
///
/// Every mpv core draws into a surface of its own, composited behind the
/// Flutter view — right for a full-screen player, and invisible for a preview
/// drawn beside other content, because pre-36 Android orders surfaces in three
/// coarse buckets and cannot put one in front of the page and nothing else
/// (see `PlayerSurfaceHost.createVideoSurface`). Such a picture has to be a
/// Flutter texture, which is what [inlineSurface] asks the core for — the same
/// arrangement the ExoPlayer backend already offers.
///
/// [VideoRectTarget] rides along for the size: a texture is positioned by the
/// widget tree, but its buffer still has to be told how many pixels the box is
/// worth. Without a texture the native side answers `no-texture` and the
/// full-screen session keeps placing its own surface, exactly as before.
class PlayerAndroidMpv extends PlayerNative implements VideoTextureTarget, VideoRectTarget {
  PlayerAndroidMpv({super.hardwareDecoding});

  /// Whether this player's picture goes in a box rather than over the window.
  ///
  /// Must be set *before* the first call that initializes the core: the core
  /// builds its whole render scaffold on the answer, and a surface born behind
  /// the Flutter view cannot be lifted above it afterwards.
  bool inlineSurface = false;

  final ValueNotifier<int?> _videoTextureId = ValueNotifier<int?>(null);

  @override
  ValueListenable<int?> get videoTextureId => _videoTextureId;

  @override
  Future<Map<String, Object?>> platformInitializeArguments() async {
    if (!inlineSurface) return const {};
    // Before initialize: the core takes this texture's surface as its video
    // output instead of building a window surface of its own.
    _videoTextureId.value = await invoke<int>('createTextureOutput');
    return const {'inlineSurface': true};
  }

  @override
  Future<void> setVideoRect({
    required int left,
    required int top,
    required int right,
    required int bottom,
    required double devicePixelRatio,
  }) async {
    final outcome = await invoke<String>('setVideoRect', {
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
      'devicePixelRatio': devicePixelRatio,
    });
    // Debug rather than info: this fires on every layout pass, and it only
    // matters while chasing a picture that is not showing up.
    appLogger.d('Video rect $left,$top → $right,$bottom (dpr $devicePixelRatio): ${outcome ?? 'no answer'}');
  }

  @override
  Future<void> dispose({bool preserveDisplayMode = false}) async {
    await super.dispose(preserveDisplayMode: preserveDisplayMode);
    _videoTextureId.dispose();
  }
}
