import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/services/live_stall_guard.dart';

/// A player whose playhead, play state and file events the test drives.
class _StreamPlayer implements Player {
  final started = StreamController<void>.broadcast();
  final playingState = StreamController<bool>.broadcast();
  final ends = StreamController<bool>.broadcast();
  final positions = StreamController<Duration>.broadcast();

  @override
  late final PlayerStreams streams = PlayerStreams(
    playing: playingState.stream,
    completed: ends.stream,
    buffering: const Stream.empty(),
    position: positions.stream,
    duration: const Stream.empty(),
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
    playbackRestart: const Stream.empty(),
    fileStarted: started.stream,
    fileLoaded: const Stream.empty(),
    primaryMediaReady: const Stream.empty(),
    fileLoadFailed: const Stream.empty(),
    backendSwitched: const Stream.empty(),
  );

  Future<void> close() => Future.wait([started.close(), playingState.close(), ends.close(), positions.close()]);

  Duration _at = Duration.zero;

  /// The playhead moves on by [step], as a playing stream reports it.
  void advance([Duration step = const Duration(milliseconds: 500)]) {
    _at += step;
    positions.add(_at);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

_StreamPlayer _player() {
  final player = _StreamPlayer();
  addTearDown(player.close);
  return player;
}

/// Plays [seconds] of stream on [player], half a second at a time.
void _play(FakeAsync async, _StreamPlayer player, int seconds) {
  for (var i = 0; i < seconds * 2; i++) {
    player.advance();
    async.elapse(const Duration(milliseconds: 500));
  }
}

void main() {
  group('LiveStallGuard', () {
    test('a stream that keeps playing is left alone', () {
      fakeAsync((async) {
        final player = _player();
        final stalls = <String>[];
        final guard = LiveStallGuard()..armForOpen(player, playing: true, onStalled: stalls.add);
        player.started.add(null);
        _play(async, player, 120);
        expect(stalls, isEmpty);
        expect(guard.isWatching, isTrue);
        guard.disarm();
      });
    });

    test('a playhead that stands still while playing is reported once', () {
      fakeAsync((async) {
        final player = _player();
        final stalls = <String>[];
        final guard = LiveStallGuard()..armForOpen(player, playing: true, onStalled: stalls.add);
        player.started.add(null);
        _play(async, player, 30);
        async.elapse(const Duration(seconds: 9));
        expect(stalls, isEmpty, reason: 'a buffer refill gets its time');
        async.elapse(const Duration(seconds: 2));
        expect(stalls, hasLength(1));
        expect(stalls.single, contains('stood still'));
        expect(guard.isWatching, isFalse);
        async.elapse(const Duration(minutes: 1));
        expect(stalls, hasLength(1));
      });
    });

    test('a stream that reported its end is reopened sooner', () {
      fakeAsync((async) {
        final player = _player();
        final stalls = <String>[];
        LiveStallGuard().armForOpen(player, playing: true, onStalled: stalls.add);
        player.started.add(null);
        _play(async, player, 30);
        player.ends.add(true);
        async.elapse(const Duration(seconds: 4));
        expect(stalls.single, contains('ended'));
      });
    });

    test('an HLS end that plays on is not a stall', () {
      fakeAsync((async) {
        final player = _player();
        final stalls = <String>[];
        final guard = LiveStallGuard()..armForOpen(player, playing: true, onStalled: stalls.add);
        player.started.add(null);
        _play(async, player, 30);
        player.ends.add(true);
        async.elapse(const Duration(seconds: 1));
        _play(async, player, 30);
        expect(stalls, isEmpty);
        guard.disarm();
      });
    });

    test('a paused stream is not judged', () {
      fakeAsync((async) {
        final player = _player();
        final stalls = <String>[];
        final guard = LiveStallGuard()..armForOpen(player, playing: true, onStalled: stalls.add);
        player.started.add(null);
        _play(async, player, 10);
        player.playingState.add(false);
        async.elapse(const Duration(minutes: 5));
        expect(stalls, isEmpty);
        player.playingState.add(true);
        async.elapse(const Duration(seconds: 11));
        expect(stalls, hasLength(1), reason: 'the clock starts again with play');
        guard.disarm();
      });
    });

    test('nothing is judged before the open starts its file', () {
      fakeAsync((async) {
        final player = _player();
        final stalls = <String>[];
        final guard = LiveStallGuard()..armForOpen(player, playing: true, onStalled: stalls.add);
        async.elapse(const Duration(minutes: 2));
        expect(stalls, isEmpty);
        guard.disarm();
      });
    });

    test('an open that started its file but never moved is reported after the start limit', () {
      fakeAsync((async) {
        final player = _player();
        final stalls = <String>[];
        LiveStallGuard().armForOpen(player, playing: true, onStalled: stalls.add);
        player.started.add(null);
        async.elapse(const Duration(seconds: 15));
        expect(stalls, isEmpty, reason: 'the open guards act first');
        async.elapse(const Duration(seconds: 6));
        expect(stalls.single, contains('never got going'));
      });
    });

    test('a stream taken over as it plays is watched at once', () {
      fakeAsync((async) {
        final player = _player();
        final stalls = <String>[];
        LiveStallGuard().armPlaying(player, playing: true, onStalled: stalls.add);
        _play(async, player, 20);
        async.elapse(const Duration(seconds: 11));
        expect(stalls.single, contains('stood still'));
      });
    });

    test('disarming ends the watch', () {
      fakeAsync((async) {
        final player = _player();
        final stalls = <String>[];
        final guard = LiveStallGuard()..armForOpen(player, playing: true, onStalled: stalls.add);
        player.started.add(null);
        _play(async, player, 10);
        guard.disarm();
        async.elapse(const Duration(minutes: 1));
        expect(stalls, isEmpty);
        expect(guard.isWatching, isFalse);
      });
    });
  });

  group('LiveStallReopenBudget', () {
    test('three reopens close together, then the viewer decides', () {
      final budget = LiveStallReopenBudget();
      final start = DateTime(2026, 10, 19, 20);
      expect(budget.take(start), isTrue);
      expect(budget.take(start.add(const Duration(seconds: 20))), isTrue);
      expect(budget.take(start.add(const Duration(seconds: 40))), isTrue);
      expect(budget.take(start.add(const Duration(seconds: 60))), isFalse);
    });

    test('a channel that played a while in between starts a new run', () {
      final budget = LiveStallReopenBudget();
      final start = DateTime(2026, 10, 19, 20);
      for (var i = 0; i < 10; i++) {
        expect(budget.take(start.add(Duration(minutes: 2 * i))), isTrue);
      }
    });

    test('a reset refills it', () {
      final budget = LiveStallReopenBudget();
      final start = DateTime(2026, 10, 19, 20);
      for (var i = 0; i < 4; i++) {
        budget.take(start.add(Duration(seconds: i)));
      }
      budget.reset();
      expect(budget.take(start.add(const Duration(seconds: 5))), isTrue);
    });
  });
}
