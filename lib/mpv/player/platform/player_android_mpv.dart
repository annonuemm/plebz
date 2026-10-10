import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;

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
class PlayerAndroidMpv extends PlayerNative
    implements VideoTextureTarget, VideoRectTarget, VideoOutputHandover, VideoViewportTarget {
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
    if (followsVideoRect) return const {'followsVideoRect': true};
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
    if (videoRectDriven) return;
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
  bool followsVideoRect = false;

  @override
  bool videoRectDriven = false;

  @override
  Future<void> driveVideoRect({required int left, required int top, required int right, required int bottom}) async {
    if (disposed) return;
    await invoke<String>('setVideoRect', {'left': left, 'top': top, 'right': right, 'bottom': bottom});
  }

  @override
  bool get rendersToTexture => _videoTextureId.value != null;

  @override
  Future<bool> moveOutputToWindow() async {
    if (disposed || !initialized || _videoTextureId.value == null) return false;
    final moved = await invoke<bool>('moveOutputToWindow') ?? false;
    if (!moved || disposed) return false;
    // The answer comes a few frames after the decoder was repointed; one more
    // gives the display time to show the window's picture before the texture
    // over it goes.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (disposed) return false;
    inlineSurface = false;
    _videoTextureId.value = null;
    // The texture goes once Flutter has drawn a frame without it.
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await invoke<bool>('releaseTextureOutput');
    return true;
  }

  @override
  Future<bool> moveOutputToTexture({required int width, required int height}) async {
    if (disposed || !initialized || _videoTextureId.value != null) return false;
    final textureId = await invoke<int>('moveOutputToTexture', {'width': width, 'height': height});
    if (textureId == null || disposed) return false;
    inlineSurface = true;
    _videoTextureId.value = textureId;
    return true;
  }

  @override
  Future<void> releaseWindowOutput() async {
    if (disposed) return;
    await invoke<void>('releaseWindowOutput');
  }

  @override
  Future<void> dispose({bool preserveDisplayMode = false}) async {
    await super.dispose(preserveDisplayMode: preserveDisplayMode);
    _videoTextureId.dispose();
  }
}
