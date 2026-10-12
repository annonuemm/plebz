import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/livetv_channel.dart';
import '../mpv/mpv.dart';
import '../mpv/player/platform/player_android_mpv.dart';
import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';
import 'playback_open_outcome.dart';
import 'settings_service.dart';

// Software decoding for the live channels a phone's hardware decoder cannot
// show (Plebz).
//
// A satellite channel relayed unchanged — interlaced 1080i/576i, often
// MPEG-2 in SD — is what television chips are built for and what many phone
// chips are not: the stream opens, keeps arriving, and no frame ever comes,
// on every player, because every player hands it to the same decoder. With
// hardware decoding switched off it plays. Switching it off for everything
// would put a phone's films in software too, so only the channels that need
// it go there:
//
// - a live open on a phone or tablet tries hardware first, and
//   [LiveSoftwareDecodeGuard] watches it; MPEG-2 without a hardware decoder
//   goes to software at once (decided natively, where the codec is known);
// - a channel that showed no picture is reopened in software and remembered
//   on this device ([PlebzPrefs.liveSoftwareDecodeChannels]), so the next
//   open starts in software without the wait.
//
// mpv only: ExoPlayer has no software path of its own for these streams.

/// The native property `MpvPlayerCore` takes in the next file's preloaded
/// hook — the only point where the decoder is chosen.
const String liveDecodeProperty = 'plebz-live-decode';

/// How many remembered channels are kept; the oldest go first.
const int liveSoftwareDecodeMemoryLimit = 200;

/// What a live open asks the decoder for. The names are the native values.
enum LiveDecodeMode {
  /// Nothing said: a television, ExoPlayer, or hardware decoding off.
  untouched,

  /// Hardware first, watched by [LiveSoftwareDecodeGuard].
  guarded,

  /// Software from the start: this channel showed no picture in hardware here.
  software,
}

/// Phones and tablets. A television chip decodes broadcast streams; the
/// layout a box is set to does not change its decoder.
bool get liveSoftwareDecodeAppliesHere => Platform.isAndroid && !PlatformDetector.isTvDevice();

/// The key a channel is remembered under: the same scope the last-selection
/// memory uses, so two sources carrying a channel of the same name stay apart.
String liveSoftwareDecodeKey(LiveTvChannel channel) => liveTvChannelScopeKey(channel);

@visibleForTesting
LiveDecodeMode liveDecodeModeFor({
  required bool appliesHere,
  required bool isMpv,
  required bool hardwareDecoding,
  required bool remembered,
}) {
  // Software already decodes everything when hardware decoding is off.
  if (!appliesHere || !isMpv || !hardwareDecoding) return LiveDecodeMode.untouched;
  return remembered ? LiveDecodeMode.software : LiveDecodeMode.guarded;
}

/// Tells [player] how to decode the next open of [channel], and returns what
/// it was told. Untouched when there is nothing to say or the word could not
/// be delivered — the channel then opens as it always did.
Future<LiveDecodeMode> applyLiveDecodeMode(Player player, LiveTvChannel? channel, {SettingsService? settings}) async {
  final svc = settings ?? SettingsService.instanceOrNull;
  if (channel == null || svc == null) return LiveDecodeMode.untouched;
  final mode = liveDecodeModeFor(
    appliesHere: liveSoftwareDecodeAppliesHere,
    isMpv: player is PlayerAndroidMpv,
    hardwareDecoding: svc.read(SettingsService.enableHardwareDecoding),
    remembered: svc.read(PlebzPrefs.liveSoftwareDecodeChannels).contains(liveSoftwareDecodeKey(channel)),
  );
  if (mode == LiveDecodeMode.untouched) return mode;
  try {
    await player.setProperty(liveDecodeProperty, mode.name);
  } catch (e) {
    appLogger.d('Live decode mode not applied', error: e);
    return LiveDecodeMode.untouched;
  }
  if (mode == LiveDecodeMode.software) {
    appLogger.i('Live TV: ${channel.displayName} opens in software (no picture in hardware before)');
  }
  return mode;
}

/// Remembers that [channel] needs software decoding on this device.
Future<void> rememberLiveSoftwareDecode(LiveTvChannel channel, {SettingsService? settings}) async {
  final svc = settings ?? SettingsService.instanceOrNull;
  if (svc == null) return;
  final key = liveSoftwareDecodeKey(channel);
  final stored = svc.read(PlebzPrefs.liveSoftwareDecodeChannels);
  if (stored.contains(key)) return;
  final kept = [...stored, key];
  final overflow = kept.length - liveSoftwareDecodeMemoryLimit;
  await svc.write(PlebzPrefs.liveSoftwareDecodeChannels, overflow > 0 ? kept.sublist(overflow) : kept);
  appLogger.i('Live TV: ${channel.displayName} remembered for software decoding on this device');
}

/// Watches guarded live opens for a decoder that takes the stream and never
/// shows a frame.
///
/// The signature is narrow on purpose: the file loaded — the stream answered
/// and its tracks were read — no frame followed within [patience], and at
/// least [minimumCacheSeconds] of stream sits read ahead behind the decoder.
/// A stream that stopped arriving is a network fault, not a decoder one; it
/// is left to the open deadline and the recovery the player already has.
class LiveSoftwareDecodeGuard {
  LiveSoftwareDecodeGuard({this.patience = defaultPatience, Future<double?> Function(Player player)? readCacheSeconds})
    : _readCacheSeconds = readCacheSeconds ?? _demuxerCacheSeconds;

  /// Longer than the gap to the next keyframe on any ordinary channel, which
  /// is what a working decoder waits for before its first frame.
  static const Duration defaultPatience = Duration(seconds: 8);

  static const double minimumCacheSeconds = 1.0;

  final Duration patience;
  final Future<double?> Function(Player player) _readCacheSeconds;

  ({LiveTvChannel channel, LiveDecodeMode mode})? _prepared;
  _Watch? _watch;

  /// Whether an open is being watched and has not shown a frame yet.
  bool get isWatching => _watch != null;

  /// Records what the next open is: the channel and the mode
  /// [applyLiveDecodeMode] gave it.
  void prepare(LiveTvChannel? channel, LiveDecodeMode mode) {
    _prepared = channel == null ? null : (channel: channel, mode: mode);
  }

  /// Called right before the open [prepare] described, so the open's own
  /// start-file delimits what is watched. Only a guarded open is watched;
  /// anything else ends a watch still running.
  void armForOpen(Player player, {required void Function(LiveTvChannel channel) onStuck}) {
    final prepared = _prepared;
    _prepared = null;
    disarm();
    if (prepared == null || prepared.mode != LiveDecodeMode.guarded) return;

    final outcome = PlaybackOpenOutcome.arm(player);
    final watch = _Watch(outcome);
    _watch = watch;
    unawaited(
      outcome.firstFrame.then((_) {
        if (identical(_watch, watch)) _release(watch);
      }),
    );
    unawaited(
      outcome.fileLoaded.then((loaded) {
        if (!loaded || !identical(_watch, watch) || outcome.isSettled) return;
        watch.timer = Timer(patience, () => unawaited(_check(player, watch, prepared.channel, onStuck)));
      }),
    );
  }

  /// Ends any watch: a newer open, a zap, the screen going away.
  void disarm() {
    final watch = _watch;
    if (watch != null) _release(watch);
  }

  Future<void> _check(
    Player player,
    _Watch watch,
    LiveTvChannel channel,
    void Function(LiveTvChannel channel) onStuck,
  ) async {
    if (!identical(_watch, watch) || watch.outcome.isSettled) return;
    double? cached;
    try {
      cached = await _readCacheSeconds(player);
    } catch (e) {
      appLogger.d('Live decode guard: cache not read', error: e);
    }
    if (!identical(_watch, watch) || watch.outcome.isSettled) return;
    _release(watch);
    if (cached == null || cached < minimumCacheSeconds) {
      appLogger.d('Live decode guard: no picture on ${channel.displayName}, but no stream waiting either');
      return;
    }
    appLogger.i(
      'Live TV: no picture on ${channel.displayName} after ${patience.inSeconds}s with '
      '${cached.toStringAsFixed(1)}s of stream waiting: the hardware decoder is not answering',
    );
    onStuck(channel);
  }

  void _release(_Watch watch) {
    if (identical(_watch, watch)) _watch = null;
    watch.timer?.cancel();
    watch.outcome.abort('live decode guard released');
  }

  static Future<double?> _demuxerCacheSeconds(Player player) async =>
      double.tryParse(await player.getProperty('demuxer-cache-duration') ?? '');
}

class _Watch {
  _Watch(this.outcome);

  final PlaybackOpenOutcome outcome;
  Timer? timer;
}
