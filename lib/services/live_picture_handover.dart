import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../media/live_tv_support.dart';
import '../models/livetv_channel.dart';
import '../mpv/mpv.dart';
import '../mpv/player/platform/player_android.dart';
import '../mpv/player/video_rect_support.dart';
import '../utils/app_logger.dart';
import 'iptv/iptv_live_tv_source.dart' show IptvPlaybackSession;
import 'settings_service.dart';

/// A live channel that is playing, passed between the guide's preview and the
/// full-screen player so the picture never stops (Plebz).
///
/// The preview plays on the television's video surface, behind a hole in the
/// guide, and hands its player over on the second press instead of stopping
/// it; the player screen takes that very player on and grows the surface out
/// of the box with the page. Back does the reverse through
/// [LivePictureReturn]. Whoever holds one owns its
/// player and session: it plays them on or [release]s them.
class LivePictureHandover {
  LivePictureHandover({required this.player, required this.session, required this.channel});

  final Player player;
  final LiveTvPlaybackSession session;
  final LiveTvChannel channel;

  /// The player can still be handed on.
  bool get isAlive => !player.disposed;

  /// Stops the picture, for a hand-over nobody took up.
  Future<void> release() async {
    appLogger.d('Live picture: releasing ${channel.displayName}');
    try {
      await session.discard();
    } catch (e) {
      appLogger.d('Live picture: session discard failed', error: e);
    }
    try {
      await player.dispose();
    } catch (e) {
      appLogger.d('Live picture: player dispose failed', error: e);
    }
  }

  /// Whether the settings let a live picture be handed over at all.
  ///
  /// Anything that switches the display when the full-screen player starts
  /// would black the screen out right where the picture was meant to carry
  /// on, so the live frame-rate match and live tunnelling must be off. Turning
  /// the switch on turns both off ([turnOffWhatInterrupts]); this checks again
  /// in case they came back by another way. The resolution match is skipped
  /// for live TV while the switch is on (the player screen's rule).
  static bool enabledIn(SettingsService settings, {bool? isAndroid}) {
    if (!(isAndroid ?? Platform.isAndroid)) return false;
    if (!settings.read(SettingsService.liveTvSeamlessFullscreen)) return false;
    final matchesFrameRate = SettingsService.matchContentFrameRateFor(
      isLive: true,
      enabled: settings.read(SettingsService.matchContentFrameRate),
      enabledForLiveTv: settings.read(SettingsService.matchContentFrameRateLiveTv),
    );
    final tunnels =
        settings.useExoPlayerFor(iptv: true) &&
        SettingsService.tunneledPlaybackFor(
          isLive: true,
          enabled: settings.read(SettingsService.tunneledPlayback),
          enabledForLiveTv: settings.read(SettingsService.tunneledPlaybackLiveTv),
        );
    return !matchesFrameRate && !tunnels;
  }

  /// Whether [player] plays on the video plane in a box — the preview a
  /// picture is handed over from.
  static bool isOnPlane(Player player) => switch (player) {
    final VideoViewportTarget target => target.followsVideoRect,
    _ => false,
  };

  /// Whether this picture can be handed between the guide and the player.
  ///
  /// IPTV only: a playlist stream is just opened, while a server's live
  /// session (a Plex tune, a Jellyfin stream) carries reporting the hand-over
  /// would have to keep alive across two screens. Not ExoPlayer's mpv
  /// fallback, which the preview never placed in its box.
  static bool canMove(Player player, LiveTvPlaybackSession? session) {
    if (session is! IptvPlaybackSession) return false;
    if (player is! VideoOutputHandover || player.disposed) return false;
    if (player is PlayerAndroid && player.usingMpvFallback) return false;
    return true;
  }

  /// Turning the switch on turns off what would interrupt the picture: the
  /// frame-rate match and tunnelling, for live TV only — films and shows keep
  /// theirs.
  static Future<void> turnOffWhatInterrupts(SettingsService settings) async {
    await settings.write(SettingsService.matchContentFrameRateLiveTv, false);
    await settings.write(SettingsService.tunneledPlaybackLiveTv, false);
  }
}

/// The way back: the full-screen player leaves its picture here, and the
/// guide's preview takes it up as it comes back into view.
///
/// A picture nobody takes within [_expiry] — the guide went away in the
/// meantime — is released, so a stream never plays on unseen.
class LivePictureReturn extends ChangeNotifier {
  LivePictureReturn._();

  static final LivePictureReturn instance = LivePictureReturn._();

  static const Duration _expiry = Duration(seconds: 5);

  LivePictureHandover? _waiting;
  Timer? _expiryTimer;

  @visibleForTesting
  bool get hasPicture => _waiting != null;

  void leave(LivePictureHandover picture) {
    _discard();
    _waiting = picture;
    _expiryTimer = Timer(_expiry, _discard);
    notifyListeners();
  }

  LivePictureHandover? take() {
    final picture = _waiting;
    _waiting = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    return picture;
  }

  void _discard() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final picture = _waiting;
    _waiting = null;
    if (picture == null) return;
    appLogger.d('Live picture: the guide did not take ${picture.channel.displayName} back');
    unawaited(picture.release());
  }
}
