import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/services/iptv/iptv_live_tv_source.dart';
import 'package:plezy/services/live_variant_fallback.dart';

/// A player whose load-scoped streams the test drives directly.
class _StreamPlayer implements Player {
  final started = StreamController<void>.broadcast();
  final loaded = StreamController<void>.broadcast();
  final restarted = StreamController<void>.broadcast();
  final primaryReady = StreamController<void>.broadcast();
  final failed = StreamController<void>.broadcast();
  final durations = StreamController<Duration>.broadcast();

  @override
  PlayerState state = const PlayerState();

  final ended = StreamController<bool>.broadcast();

  @override
  late final PlayerStreams streams = PlayerStreams(
    playing: const Stream.empty(),
    completed: ended.stream,
    buffering: const Stream.empty(),
    position: const Stream.empty(),
    duration: durations.stream,
    seekable: const Stream.empty(),
    buffer: const Stream.empty(),
    volume: const Stream.empty(),
    rate: const Stream.empty(),
    tracks: const Stream.empty(),
    track: const Stream.empty(),
    log: const Stream.empty(),
    error: const Stream.empty(),
    audioDevice: const Stream.empty(),
    audioDevices: const Stream.empty(),
    bufferRanges: const Stream.empty(),
    playbackRestart: restarted.stream,
    fileStarted: started.stream,
    fileLoaded: loaded.stream,
    // Open, not empty: an outcome reads a closed load stream as a disposed
    // player and settles at once.
    primaryMediaReady: primaryReady.stream,
    fileLoadFailed: failed.stream,
    backendSwitched: const Stream.empty(),
  );

  /// The open's start-file, as mpv reports it.
  void start() => started.add(null);

  Future<void> close() => Future.wait([
    started.close(),
    loaded.close(),
    restarted.close(),
    primaryReady.close(),
    failed.close(),
    durations.close(),
    ended.close(),
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

IptvPlaybackSession _session({required int copies, int playing = 0}) => IptvPlaybackSession(
  variants: [
    for (var i = 0; i < copies; i++)
      (url: 'http://provider.test/live/$i.ts', headers: const {}, label: 'Copy ${i + 1}'),
  ],
  variantIndex: playing,
);

/// A guard whose player names the file format [format].
LiveVariantFallbackGuard _guard({String? format = 'mp4', bool? dynamic}) =>
    LiveVariantFallbackGuard(readShape: (_) async => (format: format, dynamic: dynamic));

void main() {
  group('nextLiveVariant', () {
    test('the copy after the one playing', () {
      expect(nextLiveVariant(_session(copies: 3)), 1);
      expect(nextLiveVariant(_session(copies: 3, playing: 1)), 2);
    });

    test('none after the last copy, and none for a channel with one address', () {
      expect(nextLiveVariant(_session(copies: 3, playing: 2)), isNull);
      expect(nextLiveVariant(_session(copies: 1)), isNull);
    });
  });

  group('LiveVariantFallbackGuard', () {
    late _StreamPlayer player;

    setUp(() => player = _StreamPlayer());
    tearDown(() => player.close());

    test('a copy without a picture after five seconds names the next copy once', () {
      fakeAsync((async) {
        final stuck = <int>[];
        final guard = _guard()..armForOpen(player, _session(copies: 3), onStuck: stuck.add);
        player.start();
        async.flushMicrotasks();
        expect(guard.isWatching, isTrue);

        async.elapse(const Duration(milliseconds: 4900));
        expect(stuck, isEmpty);

        async.elapse(const Duration(milliseconds: 200));
        expect(stuck, [1]);
        expect(guard.isWatching, isFalse);

        async.elapse(const Duration(seconds: 30));
        expect(stuck, hasLength(1));
      });
    });

    test('counts from the open, whether or not the stream answered', () {
      fakeAsync((async) {
        final stuck = <int>[];
        _guard().armForOpen(player, _session(copies: 2), onStuck: stuck.add);
        async.elapse(const Duration(seconds: 6));
        expect(stuck, [1]);
      });
    });

    test('a copy that turns out to be a short clip names the next copy at once', () {
      fakeAsync((async) {
        final stuck = <int>[];
        final guard = _guard()..armForOpen(player, _session(copies: 3), onStuck: stuck.add);
        player.start();
        player.durations.add(Duration.zero);
        async.elapse(const Duration(milliseconds: 300));
        expect(stuck, isEmpty);

        player.durations.add(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(stuck, [1]);
        expect(guard.isWatching, isFalse);

        async.elapse(const Duration(seconds: 30));
        expect(stuck, hasLength(1));
      });
    });

    test('a clip whose length comes just after its first frame is still moved past', () {
      fakeAsync((async) {
        final stuck = <int>[];
        final guard = _guard()..armForOpen(player, _session(copies: 2), onStuck: stuck.add);
        player.start();
        player.restarted.add(null);
        async.elapse(const Duration(seconds: 1));
        expect(guard.isWatching, isTrue);

        player.durations.add(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(stuck, [1]);
      });
    });

    test('a long file is a channel playing a film, not an off-air clip', () {
      fakeAsync((async) {
        final stuck = <int>[];
        _guard().armForOpen(player, _session(copies: 2), onStuck: stuck.add);
        player.start();
        player.durations.add(const Duration(minutes: 95));
        player.restarted.add(null);
        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
      });
    });

    test('a length reported before the open started belongs to the file before', () {
      fakeAsync((async) {
        final stuck = <int>[];
        _guard().armForOpen(player, _session(copies: 2), onStuck: stuck.add);
        player.durations.add(const Duration(seconds: 10));
        player.start();
        player.restarted.add(null);
        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
      });
    });

    test('ExoPlayer: a finished HLS playlist is caught at its load, without a start-file', () {
      fakeAsync((async) {
        final stuck = <int>[];
        _guard(format: null, dynamic: false).armForOpen(player, _session(copies: 3), onStuck: stuck.add);
        player.loaded.add(null);
        player.durations.add(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(stuck, [1]);
      });
    });

    test('ExoPlayer: a growing HLS window is a channel', () {
      fakeAsync((async) {
        final stuck = <int>[];
        _guard(format: null, dynamic: true).armForOpen(player, _session(copies: 3), onStuck: stuck.add);
        // The test player's first frame counts after a start-file, as mpv's.
        player.start();
        player.loaded.add(null);
        player.durations.add(const Duration(seconds: 30));
        player.restarted.add(null);
        async.elapse(const Duration(minutes: 2));
        expect(stuck, isEmpty);
      });
    });

    test('a copy whose stream ends soon after its open was a clip, whatever the player said', () {
      fakeAsync((async) {
        final stuck = <int>[];
        final guard = _guard(format: 'hls')..armForOpen(player, _session(copies: 3), onStuck: stuck.add);
        player.start();
        player.durations.add(const Duration(seconds: 10));
        player.restarted.add(null);
        async.elapse(const Duration(seconds: 10));
        expect(stuck, isEmpty);
        expect(guard.isWatching, isTrue);

        player.ended.add(true);
        async.flushMicrotasks();
        expect(stuck, [1]);
      });
    });

    test('an end long after the open is left to the stall guard', () {
      fakeAsync((async) {
        final stuck = <int>[];
        final guard = _guard(format: 'hls')..armForOpen(player, _session(copies: 3), onStuck: stuck.add);
        player.start();
        player.restarted.add(null);
        async.elapse(LiveVariantFallbackGuard.offAirClipLimit);
        expect(guard.isWatching, isFalse);
        player.ended.add(true);
        async.flushMicrotasks();
        expect(stuck, isEmpty);
      });
    });

    test('an HLS channel reporting its playlist window is not a clip', () {
      fakeAsync((async) {
        final stuck = <int>[];
        final guard = _guard(format: 'hls')..armForOpen(player, _session(copies: 6), onStuck: stuck.add);
        player.start();
        for (final ms in const [927, 1010, 4611, 5024]) {
          player.durations.add(Duration(milliseconds: ms));
        }
        player.restarted.add(null);
        async.elapse(const Duration(minutes: 2));
        expect(stuck, isEmpty);
        expect(guard.isWatching, isFalse);
      });
    });

    test('a format that cannot be read is given the benefit of the doubt', () {
      fakeAsync((async) {
        final stuck = <int>[];
        LiveVariantFallbackGuard(
          readShape: (_) async => throw StateError('no core'),
        ).armForOpen(player, _session(copies: 2), onStuck: stuck.add);
        player.start();
        player.durations.add(const Duration(seconds: 10));
        player.restarted.add(null);
        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
      });
    });

    test('isOffAirClip', () {
      LiveFileShape mpv(String? format) => (format: format, dynamic: null);
      expect(isOffAirClip(Duration.zero, mpv('mp4')), isFalse);
      expect(isOffAirClip(const Duration(seconds: 10), mpv('mp4')), isTrue);
      expect(isOffAirClip(const Duration(seconds: 10), mpv('mpegts')), isTrue);
      expect(isOffAirClip(const Duration(seconds: 60), mpv('mov,mp4,m4a,3gp,3g2,mj2')), isTrue);
      expect(isOffAirClip(const Duration(seconds: 61), mpv('mp4')), isFalse);
      expect(isOffAirClip(const Duration(seconds: 4), mpv('hls')), isFalse);
      expect(isOffAirClip(const Duration(seconds: 4), mpv('applehttp')), isFalse);
      expect(isOffAirClip(const Duration(seconds: 10), mpv(null)), isFalse);
      // ExoPlayer: a finished HLS playlist is a clip, a growing one a channel.
      expect(isOffAirClip(const Duration(seconds: 10), (format: null, dynamic: false)), isTrue);
      expect(isOffAirClip(const Duration(seconds: 30), (format: null, dynamic: true)), isFalse);
      expect(isOffAirClip(const Duration(seconds: 90), (format: null, dynamic: false)), isFalse);
    });

    test('a picture within the patience ends the watch', () {
      fakeAsync((async) {
        final stuck = <int>[];
        final guard = _guard()..armForOpen(player, _session(copies: 3), onStuck: stuck.add);
        player.start();
        async.elapse(const Duration(seconds: 2));
        player.restarted.add(null);
        async.flushMicrotasks();
        expect(guard.isWatching, isTrue, reason: 'the length is still listened for');

        async.elapse(LiveVariantFallbackGuard.offAirClipLimit);
        expect(guard.isWatching, isFalse);

        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
      });
    });

    test('without recovery of its own, a failed load moves on', () {
      fakeAsync((async) {
        final stuck = <int>[];
        final guard = _guard()..armForOpen(player, _session(copies: 3), onStuck: stuck.add, moveOnFailure: true);
        player.start();
        async.elapse(const Duration(seconds: 1));
        player.failed.add(null);
        async.flushMicrotasks();
        expect(stuck, [1]);
        expect(guard.isWatching, isFalse);
      });
    });

    test('a load that fails is left to recovery', () {
      fakeAsync((async) {
        final stuck = <int>[];
        final guard = _guard()..armForOpen(player, _session(copies: 3), onStuck: stuck.add);
        player.start();
        async.elapse(const Duration(seconds: 1));
        player.failed.add(null);
        async.flushMicrotasks();
        expect(guard.isWatching, isFalse);

        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
      });
    });

    test('the last copy and a single-address channel are not watched', () {
      fakeAsync((async) {
        final stuck = <int>[];
        final guard = _guard()..armForOpen(player, _session(copies: 3, playing: 2), onStuck: stuck.add);
        expect(guard.isWatching, isFalse);
        guard.armForOpen(player, _session(copies: 1), onStuck: stuck.add);
        expect(guard.isWatching, isFalse);

        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
      });
    });

    test('a newer open replaces the watch, and disarm ends it', () {
      fakeAsync((async) {
        final stuck = <int>[];
        final guard = _guard()..armForOpen(player, _session(copies: 3), onStuck: stuck.add);
        async.elapse(const Duration(seconds: 4));
        guard.armForOpen(player, _session(copies: 3, playing: 1), onStuck: stuck.add);
        async.elapse(const Duration(seconds: 4));
        expect(stuck, isEmpty, reason: 'the first watch was replaced, the second has a second left');

        async.elapse(const Duration(seconds: 2));
        expect(stuck, [2]);

        guard.armForOpen(player, _session(copies: 4, playing: 2), onStuck: stuck.add);
        guard.disarm();
        async.elapse(const Duration(seconds: 30));
        expect(stuck, [2]);
      });
    });
  });

  group('LiveVariantFallbackGuard.watchPlaying', () {
    late _StreamPlayer player;

    setUp(() => player = _StreamPlayer());
    tearDown(() => player.close());

    test('a copy handed over before its first frame keeps the time it had left', () {
      fakeAsync((async) {
        final stuck = <int>[];
        // The guard reads the wall clock, which fake time does not move.
        final since = DateTime.now().subtract(const Duration(seconds: 3));
        final guard = _guard()..watchPlaying(player, _session(copies: 3), since: since, onStuck: stuck.add);
        expect(guard.isWatching, isTrue);

        async.elapse(const Duration(milliseconds: 1900));
        expect(stuck, isEmpty);
        async.elapse(const Duration(milliseconds: 200));
        expect(stuck, [1]);
      });
    });

    test('a handed-over copy that shows its first frame is let go', () {
      fakeAsync((async) {
        final stuck = <int>[];
        final guard = _guard()..watchPlaying(player, _session(copies: 3), since: DateTime.now(), onStuck: stuck.add);
        async.elapse(const Duration(seconds: 1));
        player.restarted.add(null);
        async.elapse(LiveVariantFallbackGuard.offAirClipLimit);
        expect(guard.isWatching, isFalse);
        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
      });
    });

    test('a handed-over copy already showing a picture is only checked for its length', () {
      fakeAsync((async) {
        final stuck = <int>[];
        player.state = const PlayerState(hasRenderedFrame: true, duration: Duration(seconds: 10));
        _guard().watchPlaying(player, _session(copies: 2), since: DateTime.now(), onStuck: stuck.add);
        async.flushMicrotasks();
        expect(stuck, [1], reason: 'the clip had already said how long it is');
      });
    });

    test('a late length on a handed-over HLS copy is its window, not a clip', () {
      fakeAsync((async) {
        final stuck = <int>[];
        player.state = const PlayerState(hasRenderedFrame: true);
        _guard(format: 'hls').watchPlaying(player, _session(copies: 2), since: DateTime.now(), onStuck: stuck.add);
        player.durations.add(const Duration(seconds: 4));
        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
      });
    });

    test('a handed-over copy that already ended moves on at once', () {
      final stuck = <int>[];
      player.state = const PlayerState(hasRenderedFrame: true, completed: true);
      _guard(format: 'hls').watchPlaying(player, _session(copies: 2), since: DateTime.now(), onStuck: stuck.add);
      expect(stuck, [1]);
    });

    test('the last copy is not watched', () {
      final guard = _guard()
        ..watchPlaying(player, _session(copies: 2, playing: 1), since: DateTime.now(), onStuck: (_) {});
      expect(guard.isWatching, isFalse);
    });
  });

  group('LiveCopyMemory', () {
    setUp(LiveCopyMemory.resetForTest);

    test('a channel opens on the copy the guard last moved to, for half an hour', () {
      final now = DateTime(2026, 10, 21, 18);
      expect(LiveCopyMemory.startIndexFor('nitro', 6, now: now), 0);
      LiveCopyMemory.remember('nitro', 1, now: now);
      expect(LiveCopyMemory.startIndexFor('nitro', 6, now: now.add(const Duration(minutes: 29))), 1);
      expect(LiveCopyMemory.startIndexFor('nitro', 6, now: now.add(const Duration(minutes: 31))), 0);
    });

    test('a remembered copy the playlist no longer has is forgotten', () {
      LiveCopyMemory.remember('nitro', 4);
      expect(LiveCopyMemory.startIndexFor('nitro', 3), 0);
    });

    test('the guard remembers where it moved a merged channel', () {
      fakeAsync((async) {
        final player = _StreamPlayer();
        final session = _session(copies: 3);
        _guard(format: 'hls').armForOpen(player, session, onStuck: (_) {});
        player.start();
        player.ended.add(true);
        async.flushMicrotasks();
        expect(LiveCopyMemory.startIndexFor(session.copyMemoryKey!, 3), 1);
        unawaited(player.close());
      });
    });
  });
}
