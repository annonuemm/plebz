import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/live_tv_support.dart';
import '../mpv/mpv.dart';
import '../utils/app_logger.dart';
import 'playback_open_outcome.dart';

// Moving on to a merged channel's next copy when the one opened is not the
// channel (Plebz).
//
// A station a playlist carries several times over is one channel once the
// copies are merged, and the first copy is what opens. A copy that is down
// fails in one of three ways:
//
// - the load fails — the player's recovery moves to the next copy already;
// - the provider holds the connection open and no picture ever comes;
// - the provider plays a short "not on air" clip in its place: a finite file
//   of a few seconds (10 s at 30 fps on the user's provider) where a channel
//   is an endless stream. It shows a picture, then ends and stands still.
//   An HLS channel reports a length too — the few seconds its playlist
//   currently holds (0.9 to 5 s seen on the same provider) — so a short
//   length only counts for a stream that is not HLS.
//
// The copy picker lives in the player's controls, which come up with the
// first frame — in the second case never, in the third over the wrong
// picture. Both are moved past here.

/// The copy after the one [session] plays, or null when it plays the last
/// one or has only one. Forward only: a run of dead copies ends at the last
/// one instead of going round again, and recovery moves forward too.
@visibleForTesting
int? nextLiveVariant(LiveTvPlaybackSession session) {
  final next = session.variantIndex + 1;
  return next < session.variantLabels.length ? next : null;
}

/// Whether a live open whose file reports [duration] in [format] (mpv's
/// `file-format`) is a provider's stand-in clip rather than the channel. A
/// long file may be a channel that plays a film round the clock; HLS reports
/// its playlist's window as a length; an unknown format is given the benefit
/// of the doubt.
@visibleForTesting
bool isOffAirClip(Duration duration, String? format) {
  if (duration <= Duration.zero || duration > LiveVariantFallbackGuard.offAirClipLimit) return false;
  if (format == null || format.isEmpty) return false;
  return !_isHls(format);
}

/// mpv names an HLS stream `hls` (ffmpeg's demuxer); older builds said
/// `applehttp`.
bool _isHls(String format) {
  final lower = format.toLowerCase();
  return lower.contains('hls') || lower.contains('applehttp');
}

/// Watches the open of a merged channel's copy, and names the next copy when
/// no first frame came within [patience] of the open starting, or when the
/// copy turned out to be an off-air clip ([isOffAirClip]).
///
/// Only a copy with another one after it is watched. A load that fails is
/// left to the player's recovery, which moves to the next copy by itself.
class LiveVariantFallbackGuard {
  LiveVariantFallbackGuard({this.patience = defaultPatience, Future<String?> Function(Player player)? readFormat})
    : _readFormat = readFormat ?? _fileFormat;

  /// Long enough for an ordinary channel's first keyframe, short enough that
  /// a dead copy is not sat out.
  static const Duration defaultPatience = Duration(seconds: 5);

  /// The longest file taken for an off-air clip.
  static const Duration offAirClipLimit = Duration(seconds: 60);

  /// How long after the first frame a file's length is still listened for:
  /// it is usually known before the first frame, but nothing orders the two.
  static const Duration lengthGrace = Duration(seconds: 3);

  final Duration patience;
  final Future<String?> Function(Player player) _readFormat;

  _Watch? _watch;

  /// Whether an open is being watched: no frame yet, or its length not yet
  /// settled.
  bool get isWatching => _watch != null;

  /// Called right before [session]'s stream is opened on [player], so the
  /// open's own start-file delimits what is watched. Ends any watch still
  /// running. [onStuck] gets the index of the copy to try next.
  void armForOpen(Player player, LiveTvPlaybackSession session, {required void Function(int next) onStuck}) {
    disarm();
    final next = nextLiveVariant(session);
    if (next == null) return;

    final outcome = PlaybackOpenOutcome.arm(player);
    final watch = _Watch(outcome);
    _watch = watch;
    final copy = 'copy ${session.variantIndex + 1} of ${session.variantLabels.length}';

    void moveOn(String why) {
      if (!identical(_watch, watch)) return;
      _release(watch);
      appLogger.i('Live TV: $copy $why — trying copy ${next + 1}');
      onStuck(next);
    }

    // The open resets the length to zero; only what its own file reports
    // after its start-file counts. The format is read once, at the first
    // short length.
    var started = false;
    Future<String?>? format;
    Future<void> checkLength(Duration duration) async {
      if (!started || duration <= Duration.zero || duration > offAirClipLimit) return;
      final name = await (format ??= _readFormatOf(player));
      if (!identical(_watch, watch)) return;
      if (isOffAirClip(duration, name)) {
        moveOn('is a ${duration.inMilliseconds} ms $name clip, not a live stream');
      }
    }

    watch.subscriptions
      ..add(player.streams.fileStarted.listen((_) => started = true))
      ..add(player.streams.duration.listen((duration) => unawaited(checkLength(duration))));
    unawaited(
      outcome.firstFrame.then((shown) {
        if (!identical(_watch, watch)) return;
        if (!shown) {
          _release(watch);
          return;
        }
        watch.timer?.cancel();
        watch.timer = Timer(lengthGrace, () => _release(watch));
      }),
    );
    watch.timer = Timer(patience, () {
      if (outcome.isSettled) return;
      moveOn('showed no picture after ${patience.inSeconds}s');
    });
  }

  /// Ends any watch: a newer open, a zap, the screen going away.
  void disarm() {
    final watch = _watch;
    if (watch != null) _release(watch);
  }

  void _release(_Watch watch) {
    if (identical(_watch, watch)) _watch = null;
    watch.timer?.cancel();
    for (final subscription in watch.subscriptions) {
      unawaited(subscription.cancel());
    }
    watch.subscriptions.clear();
    watch.outcome.abort('live variant fallback released');
  }

  Future<String?> _readFormatOf(Player player) async {
    try {
      return await _readFormat(player);
    } catch (e) {
      appLogger.d('Live copy guard: file format not read', error: e);
      return null;
    }
  }

  static Future<String?> _fileFormat(Player player) => player.getProperty('file-format');
}

class _Watch {
  _Watch(this.outcome);

  final PlaybackOpenOutcome outcome;
  final List<StreamSubscription<Object?>> subscriptions = [];
  Timer? timer;
}
