import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/live_tv_support.dart';
import '../mpv/mpv.dart';
import '../mpv/player/platform/player_android.dart' show liveTimelineDynamicProperty;
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
// - the provider plays a short "not on air" clip in its place (10 s at 30 fps
//   on the user's provider, served at the channel's own .m3u8 address as a
//   finished HLS playlist). It shows a picture, then ends and stands still.
//
// A channel never ends, so a copy that ends within [offAirClipLimit] of its
// open is a clip, whatever the player. Where the player can tell sooner, the
// copy is moved past at once: ExoPlayer knows whether an HLS playlist is
// still growing; for mpv a short length on a stream that is not HLS will do
// (a live HLS playlist reports its few seconds of window as a length there).
//
// The copy picker lives in the player's controls, which come up with the
// first frame — for a silent copy never, for a clip over the wrong picture.

/// The copy after the one [session] plays, or null when it plays the last
/// one or has only one. Forward only: a run of dead copies ends at the last
/// one instead of going round again, and recovery moves forward too.
int? nextLiveVariant(LiveTvPlaybackSession session) {
  final next = session.variantIndex + 1;
  return next < session.variantLabels.length ? next : null;
}

/// Copies found lately not to be the channel (Plebz).
///
/// A preview that moved past an off-air copy, and the full screen opening the
/// same channel a moment later, would otherwise both start at the first copy
/// and sit through the same clip — the preview cannot always hand its picture
/// over (ExoPlayer's mpv fallback stays in its box). So a channel opens on the
/// copy the guard last moved to, for a while: an off-air copy usually comes
/// back, and then the first choice is the first choice again. Memory only;
/// nothing of it is stored.
class LiveCopyMemory {
  LiveCopyMemory._();

  /// How long a move is remembered.
  static const Duration keepFor = Duration(minutes: 30);

  static final Map<String, ({int index, DateTime at})> _startAt = {};

  /// The copy a channel known by [key] with [count] copies should open on.
  static int startIndexFor(String key, int count, {DateTime? now}) {
    final entry = _startAt[key];
    if (entry == null) return 0;
    if ((now ?? DateTime.now()).difference(entry.at) > keepFor || entry.index >= count) {
      _startAt.remove(key);
      return 0;
    }
    return entry.index;
  }

  /// The guard moved the channel known by [key] on to copy [index].
  static void remember(String key, int index, {DateTime? now}) {
    _startAt[key] = (index: index, at: now ?? DateTime.now());
  }

  @visibleForTesting
  static void resetForTest() => _startAt.clear();
}

/// What a player says about the file it plays: mpv's `file-format`, and
/// whether its timeline still grows, where the core knows (ExoPlayer).
typedef LiveFileShape = ({String? format, bool? dynamic});

/// Whether a live open whose file reports [duration] is known at once to be a
/// provider's stand-in clip rather than the channel. A long file may be a
/// channel that plays a film round the clock. A timeline that stopped growing
/// is a finished file; without that word, a stream that is not HLS will do,
/// and an unknown one is given the benefit of the doubt — its end still tells.
@visibleForTesting
bool isOffAirClip(Duration duration, LiveFileShape shape) {
  if (duration <= Duration.zero || duration > LiveVariantFallbackGuard.offAirClipLimit) return false;
  final dynamic = shape.dynamic;
  if (dynamic != null) return !dynamic;
  final format = shape.format;
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
/// no first frame came within [patience] of the open starting, when the copy
/// turned out to be an off-air clip ([isOffAirClip]), or when it ended within
/// [offAirClipLimit] of its open.
///
/// Only a copy with another one after it is watched. A load that fails is
/// left to the player's recovery, which moves to the next copy by itself.
class LiveVariantFallbackGuard {
  LiveVariantFallbackGuard({this.patience = defaultPatience, Future<LiveFileShape> Function(Player player)? readShape})
    : _readShape = readShape ?? _shapeOf;

  /// Long enough for an ordinary channel's first keyframe, short enough that
  /// a dead copy is not sat out.
  static const Duration defaultPatience = Duration(seconds: 5);

  /// The longest file taken for an off-air clip, and how long after its open
  /// a copy's end still says it was one.
  static const Duration offAirClipLimit = Duration(seconds: 60);

  final Duration patience;
  final Future<LiveFileShape> Function(Player player) _readShape;

  _Watch? _watch;

  /// Whether a copy is being watched: no frame yet, or still young enough
  /// that its end would make it a clip.
  bool get isWatching => _watch != null;

  /// When the open being watched started, or null when none is. Handed on
  /// with a picture that changes hands mid-watch ([watchPlaying]).
  DateTime? get watchingSince => _watch?.since;

  /// Called right before [session]'s stream is opened on [player], so the
  /// open's own start delimits what is watched. Ends any watch still
  /// running. [onStuck] gets the index of the copy to try next.
  ///
  /// A load that fails is the player's recovery to handle where it has one
  /// (the full screen moves on to the next copy by itself); [moveOnFailure]
  /// is for an owner without one — the guide's preview.
  void armForOpen(
    Player player,
    LiveTvPlaybackSession session, {
    required void Function(int next) onStuck,
    bool moveOnFailure = false,
  }) {
    disarm();
    final next = nextLiveVariant(session);
    if (next == null) return;

    final outcome = PlaybackOpenOutcome.arm(player);
    final watch = _Watch(DateTime.now(), player, session, next, onStuck, outcome: outcome);
    _watch = watch;
    // The open resets the length to zero; only what its own file reports
    // counts. mpv marks the file's start; ExoPlayer only its load.
    watch.subscriptions
      ..add(player.streams.fileStarted.listen((_) => watch.started = true))
      ..add(
        player.streams.fileLoaded.listen((_) {
          watch.started = true;
          unawaited(_checkLength(watch, player.state.duration));
        }),
      );
    _listen(watch);
    unawaited(
      outcome.firstFrame.then((shown) {
        if (!identical(_watch, watch)) return;
        if (shown) {
          _settleAfterFrame(watch);
        } else if (moveOnFailure) {
          // Only the guard aborts its own outcome, and it lets go of the watch
          // first: a watch still held here ended in a failed load.
          _moveOn(watch, 'could not be opened');
        } else {
          _release(watch);
        }
      }),
    );
    watch.timer = Timer(patience, () {
      if (outcome.isSettled) return;
      _moveOn(watch, 'showed no picture after ${patience.inSeconds}s');
    });
  }

  /// Takes up the watch of a copy whose open began at [since] on another
  /// owner — the guide's preview, handed to the full screen mid-open — so the
  /// hand-over neither waits for the watch to end nor drops it. Its file has
  /// started; whether it showed a frame is the player's to say.
  void watchPlaying(
    Player player,
    LiveTvPlaybackSession session, {
    required DateTime since,
    required void Function(int next) onStuck,
  }) {
    disarm();
    final next = nextLiveVariant(session);
    if (next == null) return;

    final watch = _Watch(since, player, session, next, onStuck)..started = true;
    _watch = watch;
    _listen(watch);
    if (player.state.completed) {
      _onEnded(watch);
      return;
    }
    if (player.state.hasRenderedFrame) {
      _settleAfterFrame(watch);
    } else {
      watch.subscriptions.add(
        player.streams.playbackRestart.listen((_) {
          if (identical(_watch, watch) && !watch.framed) _settleAfterFrame(watch);
        }),
      );
      final left = patience - DateTime.now().difference(since);
      watch.timer = Timer(left > _leastPatience ? left : _leastPatience, () {
        if (watch.framed) return;
        _moveOn(watch, 'showed no picture after ${patience.inSeconds}s');
      });
    }
    unawaited(_checkLength(watch, player.state.duration));
  }

  /// A copy handed over just before the deadline still gets a moment of its
  /// own.
  static const Duration _leastPatience = Duration(seconds: 1);

  /// Ends any watch: a newer open, a zap, the screen going away.
  void disarm() {
    final watch = _watch;
    if (watch != null) _release(watch);
  }

  void _listen(_Watch watch) {
    final streams = watch.player.streams;
    watch.subscriptions
      ..add(streams.duration.listen((duration) => unawaited(_checkLength(watch, duration))))
      ..add(
        streams.completed.listen((completed) {
          if (completed && watch.started) _onEnded(watch);
        }),
      );
  }

  /// A short length the watched file reported: read what the player says the
  /// file is — once per copy, logged — and move on when that makes it a clip.
  Future<void> _checkLength(_Watch watch, Duration duration) async {
    if (!watch.started || duration <= Duration.zero || duration > offAirClipLimit) return;
    final shape = await (watch.shape ??= _readShapeOf(watch));
    if (!identical(_watch, watch)) return;
    if (isOffAirClip(duration, shape)) {
      _moveOn(watch, 'is a ${duration.inMilliseconds} ms clip (${_describe(shape)}), not a live stream');
    }
  }

  Future<LiveFileShape> _readShapeOf(_Watch watch) async {
    LiveFileShape shape;
    try {
      shape = await _readShape(watch.player);
    } catch (e) {
      appLogger.d('Live copy guard: file shape not read', error: e);
      shape = (format: null, dynamic: null);
    }
    appLogger.i(
      'Live TV: ${_copy(watch)} reports a length of ${watch.player.state.duration.inMilliseconds} ms '
      '(${_describe(shape)})',
    );
    return shape;
  }

  /// The copy's stream ended. A channel never does; one that ends this soon
  /// after its open was a clip.
  void _onEnded(_Watch watch) {
    if (!identical(_watch, watch)) return;
    final age = DateTime.now().difference(watch.since);
    if (age > offAirClipLimit) return;
    _moveOn(watch, 'ended ${age.inSeconds}s after it opened — an off-air clip');
  }

  /// The copy showed a frame: it stays watched until it is old enough that
  /// its end would no longer say it was a clip.
  void _settleAfterFrame(_Watch watch) {
    watch.framed = true;
    watch.timer?.cancel();
    final left = offAirClipLimit - DateTime.now().difference(watch.since);
    watch.timer = Timer(left > Duration.zero ? left : Duration.zero, () => _release(watch));
  }

  void _moveOn(_Watch watch, String why) {
    if (!identical(_watch, watch)) return;
    _release(watch);
    appLogger.i('Live TV: ${_copy(watch)} $why — trying copy ${watch.next + 1}');
    final key = watch.session.copyMemoryKey;
    if (key != null) LiveCopyMemory.remember(key, watch.next);
    watch.onStuck(watch.next);
  }

  static String _copy(_Watch watch) =>
      'copy ${watch.session.variantIndex + 1} of ${watch.session.variantLabels.length}';

  static String _describe(LiveFileShape shape) {
    final dynamic = shape.dynamic;
    return [
      'format ${shape.format ?? 'unknown'}',
      if (dynamic != null) dynamic ? 'timeline growing' : 'timeline finished',
    ].join(', ');
  }

  void _release(_Watch watch) {
    if (identical(_watch, watch)) _watch = null;
    watch.timer?.cancel();
    for (final subscription in watch.subscriptions) {
      unawaited(subscription.cancel());
    }
    watch.subscriptions.clear();
    watch.outcome?.abort('live variant fallback released');
  }

  static Future<LiveFileShape> _shapeOf(Player player) async {
    final format = await _property(player, 'file-format');
    final dynamic = switch (await _property(player, liveTimelineDynamicProperty)) {
      'yes' => true,
      'no' => false,
      _ => null,
    };
    return (format: format, dynamic: dynamic);
  }

  /// One property, or null where the core does not know it.
  static Future<String?> _property(Player player, String name) async {
    try {
      final value = await player.getProperty(name);
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }
}

class _Watch {
  _Watch(this.since, this.player, this.session, this.next, this.onStuck, {this.outcome});

  final DateTime since;
  final Player player;
  final LiveTvPlaybackSession session;
  final int next;
  final void Function(int next) onStuck;

  /// The open's own first-frame signal; null for a copy taken up mid-open,
  /// whose first frame is read from the player.
  final PlaybackOpenOutcome? outcome;
  final List<StreamSubscription<Object?>> subscriptions = [];
  Future<LiveFileShape>? shape;
  Timer? timer;
  bool started = false;
  bool framed = false;
}
