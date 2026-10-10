import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'player_native.dart';

/// A player whose video lives in a native surface behind the Flutter window,
/// and so must be told where to put it.
///
/// `Video` keys its layout reporting off this type: implementing it is what
/// says the player has a surface worth positioning. Without it the surface
/// covers the whole window, which is right for a full-screen player and wrong
/// for anything drawn beside something else.
abstract interface class VideoRectTarget {
  Future<void> setVideoRect({
    required int left,
    required int top,
    required int right,
    required int bottom,
    required double devicePixelRatio,
  });

  /// The stream a rejected rect is reported on. Geometry is the only thing
  /// that makes the surface visible, so a failure is a black video area
  /// rather than a cosmetic glitch, and it has to reach someone.
  StreamController<PlayerError> get errorController;
}

/// A player whose picture is a Flutter texture rather than a surface of its
/// own.
///
/// The way to draw video *inside* the widget tree: a surface has to be
/// composited above or below the whole Flutter view, which is right for a
/// full-screen picture and cannot place a small one in front of the page and
/// nothing else. A texture is ordinary content and needs no such ordering.
abstract interface class VideoTextureTarget {
  /// The texture to render, or null while there is none yet.
  ValueListenable<int?> get videoTextureId;
}

/// A player whose picture can move between a Flutter texture and a surface of
/// its own while it plays: the guide's live preview growing into the
/// full-screen player and shrinking back, with the stream never stopping
/// (Plebz). Android only, on both backends.
abstract interface class VideoOutputHandover {
  /// Whether the picture is in a Flutter texture right now.
  bool get rendersToTexture;

  /// Moves the picture out of its texture onto the window surface. True once
  /// it is there; [VideoTextureTarget.videoTextureId] is null by then, and the
  /// texture is released a frame later. False when nothing moved.
  Future<bool> moveOutputToWindow();

  /// Moves the picture back into a new texture of [width] by [height]
  /// physical pixels, published on [VideoTextureTarget.videoTextureId]. The
  /// window surface stays up behind it until [releaseWindowOutput], so the
  /// picture never shows a gap while Flutter puts the texture on screen.
  Future<bool> moveOutputToTexture({required int width, required int height});

  /// Takes the window surface down after [moveOutputToTexture].
  Future<void> releaseWindowOutput();
}

/// A player whose window surface can sit in a box behind a hole in the app
/// instead of filling the screen (Plebz): the guide's live preview on the
/// video plane, which grows into the full-screen player and shrinks back with
/// no move between surfaces at all. Android only, on both backends.
abstract interface class VideoViewportTarget {
  /// Set before the core is built: the surface follows the reported rect.
  bool get followsVideoRect;

  /// While a transition moves the picture itself ([driveVideoRect]), the
  /// rects a `Video` widget reports are ignored: they describe a page under a
  /// transform, a frame late.
  set videoRectDriven(bool value);

  /// Places the picture at this box (window pixels), whatever [videoRectDriven] says.
  Future<void> driveVideoRect({required int left, required int top, required int right, required int bottom});
}

/// The desktop implementation. The request is the same on every such platform
/// — a Windows child HWND and a Wayland subsurface take identical geometry —
/// so the mixin carries the call instead of each platform repeating it.
mixin VideoRectSupport on PlayerNative implements VideoRectTarget {
  @override
  Future<void> setVideoRect({
    required int left,
    required int top,
    required int right,
    required int bottom,
    required double devicePixelRatio,
  }) async {
    await invoke('setVideoRect', {
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
      'devicePixelRatio': devicePixelRatio,
    });
  }
}
