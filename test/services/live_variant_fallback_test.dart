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
  late final PlayerStreams streams = PlayerStreams(
    playing: const Stream.empty(),
    completed: const Stream.empty(),
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
LiveVariantFallbackGuard _guard({String? format = 'mp4'}) => LiveVariantFallbackGuard(readFormat: (_) async => format);

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

    test('an HLS channel reporting its playlist window is not a clip', () {
      fakeAsync((async) {
        final stuck = <int>[];
        final guard = _guard(format: 'hls')..armForOpen(player, _session(copies: 6), onStuck: stuck.add);
        player.start();
        for (final ms in const [927, 1010, 4611, 5024]) {
          player.durations.add(Duration(milliseconds: ms));
        }
        player.restarted.add(null);
        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
        expect(guard.isWatching, isFalse);
      });
    });

    test('a format that cannot be read is given the benefit of the doubt', () {
      fakeAsync((async) {
        final stuck = <int>[];
        LiveVariantFallbackGuard(
          readFormat: (_) async => throw StateError('no core'),
        ).armForOpen(player, _session(copies: 2), onStuck: stuck.add);
        player.start();
        player.durations.add(const Duration(seconds: 10));
        player.restarted.add(null);
        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
      });
    });

    test('isOffAirClip', () {
      expect(isOffAirClip(Duration.zero, 'mp4'), isFalse);
      expect(isOffAirClip(const Duration(seconds: 10), 'mp4'), isTrue);
      expect(isOffAirClip(const Duration(seconds: 10), 'mpegts'), isTrue);
      expect(isOffAirClip(const Duration(seconds: 60), 'mov,mp4,m4a,3gp,3g2,mj2'), isTrue);
      expect(isOffAirClip(const Duration(seconds: 61), 'mp4'), isFalse);
      expect(isOffAirClip(const Duration(seconds: 4), 'hls'), isFalse);
      expect(isOffAirClip(const Duration(seconds: 4), 'applehttp'), isFalse);
      expect(isOffAirClip(const Duration(seconds: 10), null), isFalse);
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

        async.elapse(LiveVariantFallbackGuard.lengthGrace);
        expect(guard.isWatching, isFalse);

        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
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
}
