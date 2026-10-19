import 'dart:async';

import '../mpv/mpv.dart';

// Reopening a live channel whose picture stands still (Plebz).
//
// A live stream that the provider stops sending is not an error to the
// player: a connection the provider closes reads as the end of the stream,
// which live TV ignores (an HLS playlist reports transient ends too), and a
// connection that stays open without data only fails once mpv's network
// timeout runs out — a minute. Either way the picture stands still until the
// viewer zaps away and back, which opens a fresh connection.
//
// FFmpeg's own reconnect cannot stand in for this: it cannot tell a dropped
// stream from a file that ended, so reconnecting at the end of a stream
// re-requested a provider's few-second clip thousands of times and never
// started an HLS channel; without that switch it does nothing for an endless
// stream. The guard watches the playhead instead, so it covers both.

/// Watches a live stream's playhead and reports when it stood still while
/// playing: for [stallLimit] in general, for [endLimit] once the stream
/// reported its end, and for [startLimit] when an open started its file but
/// never got going.
///
/// Only counts while the player is meant to play — a pause, a frame-rate
/// hold or a backgrounded app stops the clock. Reports once per arming.
class LiveStallGuard {
  LiveStallGuard({
    this.stallLimit = defaultStallLimit,
    this.endLimit = defaultEndLimit,
    this.startLimit = defaultStartLimit,
  });

  /// A playhead that stood still this long while playing is a stream that
  /// stopped coming: well past a buffer refill on a slow connection.
  static const Duration defaultStallLimit = Duration(seconds: 10);

  /// After the stream reported its end: a transient HLS end moves on within
  /// a second or two, a closed connection never does.
  static const Duration defaultEndLimit = Duration(seconds: 3);

  /// An open whose file started but whose playhead never moved. Longer than
  /// the open guards' patience (copy fallback 5 s), which act first.
  static const Duration defaultStartLimit = Duration(seconds: 20);

  static const Duration _tick = Duration(seconds: 1);

  final Duration stallLimit;
  final Duration endLimit;
  final Duration startLimit;

  _Watch? _watch;

  /// Whether a stream is being watched.
  bool get isWatching => _watch != null;

  /// Called right before a live open on [player]: the watch begins with the
  /// open's own start-file, so the stream being replaced is never judged.
  void armForOpen(Player player, {required bool playing, required void Function(String why) onStalled}) {
    _arm(player, playing: playing, running: false, started: false, onStalled: onStalled);
  }

  /// A stream already playing on [player] — the guide's preview taken over
  /// as it plays.
  void armPlaying(Player player, {required bool playing, required void Function(String why) onStalled}) {
    _arm(player, playing: playing, running: true, started: true, onStalled: onStalled);
  }

  void _arm(
    Player player, {
    required bool playing,
    required bool running,
    required bool started,
    required void Function(String why) onStalled,
  }) {
    disarm();
    final watch = _Watch(playing: playing, running: running, started: started);
    _watch = watch;

    watch.subscriptions
      ..add(
        player.streams.fileStarted.listen((_) {
          watch
            ..started = true
            ..running = false
            ..ended = false
            ..position = null
            ..still = Duration.zero;
        }),
      )
      ..add(player.streams.playing.listen((value) => watch.playing = value))
      ..add(player.streams.completed.listen((value) => watch.ended = value))
      ..add(
        player.streams.position.listen((value) {
          if (!watch.started) return;
          final previous = watch.position;
          watch.position = value;
          if (previous != null && value != previous) {
            watch
              ..running = true
              ..still = Duration.zero;
          }
        }),
      );

    watch.timer = Timer.periodic(_tick, (_) {
      if (!identical(_watch, watch)) return;
      if (!watch.started || !watch.playing) {
        watch.still = Duration.zero;
        return;
      }
      if (watch.position != watch.positionAtTick) {
        watch
          ..positionAtTick = watch.position
          ..still = Duration.zero;
        return;
      }
      watch.still += _tick;
      final String why;
      if (!watch.running) {
        if (watch.still < startLimit) return;
        why = 'never got going within ${startLimit.inSeconds}s of its start';
      } else if (watch.ended) {
        if (watch.still < endLimit) return;
        why = 'ended and stood still for ${endLimit.inSeconds}s';
      } else {
        if (watch.still < stallLimit) return;
        why = 'stood still for ${stallLimit.inSeconds}s';
      }
      _release(watch);
      onStalled(why);
    });
  }

  /// Ends any watch: a newer open, a time-shift, the screen going away.
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
  }
}

/// How many automatic reopens in a row are tried before the viewer is asked:
/// a channel that keeps stopping (a provider's off-air loop, a dead line) is
/// not reopened forever.
const int maxLiveStallReopens = 3;

/// Reopens closer together than this count as one run; a channel that
/// played longer in between starts a new one.
const Duration liveStallReopenWindow = Duration(seconds: 90);

/// Counts automatic reopens and says whether another one may run.
class LiveStallReopenBudget {
  DateTime? _last;
  int _inRun = 0;

  /// Records a reopen at [now]; false once [maxLiveStallReopens] ran within
  /// [liveStallReopenWindow] of each other.
  bool take(DateTime now) {
    final last = _last;
    _inRun = last != null && now.difference(last) < liveStallReopenWindow ? _inRun + 1 : 1;
    _last = now;
    return _inRun <= maxLiveStallReopens;
  }

  /// A channel tuned by the viewer starts with a full budget.
  void reset() {
    _last = null;
    _inRun = 0;
  }
}

class _Watch {
  _Watch({required this.playing, required this.running, required this.started});

  bool playing;
  bool running;
  bool started;
  bool ended = false;
  Duration? position;
  Duration? positionAtTick;
  Duration still = Duration.zero;
  final List<StreamSubscription<Object?>> subscriptions = [];
  Timer? timer;
}
