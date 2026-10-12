import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/services/live_software_decode.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/prefs.dart';

/// A player whose load-scoped streams the test drives directly.
class _StreamPlayer implements Player {
  final started = StreamController<void>.broadcast();
  final loaded = StreamController<void>.broadcast();
  final restarted = StreamController<void>.broadcast();
  final primaryReady = StreamController<void>.broadcast();
  final failed = StreamController<void>.broadcast();

  @override
  late final PlayerStreams streams = PlayerStreams(
    playing: const Stream.empty(),
    completed: const Stream.empty(),
    buffering: const Stream.empty(),
    position: const Stream.empty(),
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
    playbackRestart: restarted.stream,
    fileStarted: started.stream,
    fileLoaded: loaded.stream,
    // Open, not empty: an outcome reads a closed load stream as a disposed
    // player and settles at once.
    primaryMediaReady: primaryReady.stream,
    fileLoadFailed: failed.stream,
    backendSwitched: const Stream.empty(),
  );

  /// The open's start-file and file-loaded, as mpv reports them.
  void load() {
    started.add(null);
    loaded.add(null);
  }

  Future<void> close() =>
      Future.wait([started.close(), loaded.close(), restarted.close(), primaryReady.close(), failed.close()]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final channel = LiveTvChannel(key: 'iptv:src:das-erste', serverId: 'src', title: 'Das Erste HD');

  group('liveDecodeModeFor', () {
    test('a phone with mpv and hardware decoding tries hardware first, watched', () {
      expect(
        liveDecodeModeFor(appliesHere: true, isMpv: true, hardwareDecoding: true, remembered: false),
        LiveDecodeMode.guarded,
      );
    });

    test('a channel remembered on this device opens in software', () {
      expect(
        liveDecodeModeFor(appliesHere: true, isMpv: true, hardwareDecoding: true, remembered: true),
        LiveDecodeMode.software,
      );
    });

    test('a television, ExoPlayer and software decoding are left alone', () {
      expect(
        liveDecodeModeFor(appliesHere: false, isMpv: true, hardwareDecoding: true, remembered: true),
        LiveDecodeMode.untouched,
      );
      expect(
        liveDecodeModeFor(appliesHere: true, isMpv: false, hardwareDecoding: true, remembered: true),
        LiveDecodeMode.untouched,
      );
      expect(
        liveDecodeModeFor(appliesHere: true, isMpv: true, hardwareDecoding: false, remembered: true),
        LiveDecodeMode.untouched,
      );
    });
  });

  group('LiveSoftwareDecodeGuard', () {
    late _StreamPlayer player;

    setUp(() => player = _StreamPlayer());
    tearDown(() => player.close());

    LiveSoftwareDecodeGuard guardWithCache(double? seconds) =>
        LiveSoftwareDecodeGuard(readCacheSeconds: (_) async => seconds);

    test('a stream that loads and keeps arriving without a frame is reported once', () {
      fakeAsync((async) {
        final stuck = <LiveTvChannel>[];
        final guard = guardWithCache(3.2)
          ..prepare(channel, LiveDecodeMode.guarded)
          ..armForOpen(player, onStuck: stuck.add);
        player.load();
        async.flushMicrotasks();
        expect(guard.isWatching, isTrue);

        async.elapse(const Duration(seconds: 7));
        expect(stuck, isEmpty);

        async.elapse(const Duration(seconds: 2));
        expect(stuck.map((c) => c.key), [channel.key]);
        expect(guard.isWatching, isFalse);

        async.elapse(const Duration(seconds: 30));
        expect(stuck, hasLength(1));
      });
    });

    test('a frame within the patience ends the watch', () {
      fakeAsync((async) {
        final stuck = <LiveTvChannel>[];
        final guard = guardWithCache(3.2)
          ..prepare(channel, LiveDecodeMode.guarded)
          ..armForOpen(player, onStuck: stuck.add);
        player.load();
        async.elapse(const Duration(seconds: 2));
        player.restarted.add(null);
        async.flushMicrotasks();
        expect(guard.isWatching, isFalse);

        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
      });
    });

    test('a stream that stopped arriving is not taken for a decoder fault', () {
      fakeAsync((async) {
        final stuck = <LiveTvChannel>[];
        final guard = guardWithCache(0.2)
          ..prepare(channel, LiveDecodeMode.guarded)
          ..armForOpen(player, onStuck: stuck.add);
        player.load();
        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
        expect(guard.isWatching, isFalse);
      });
    });

    test('nothing is reported before the file loaded', () {
      fakeAsync((async) {
        final stuck = <LiveTvChannel>[];
        guardWithCache(3.2)
          ..prepare(channel, LiveDecodeMode.guarded)
          ..armForOpen(player, onStuck: stuck.add);
        player.started.add(null);
        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
      });
    });

    test('only a guarded open is watched', () {
      fakeAsync((async) {
        final stuck = <LiveTvChannel>[];
        for (final mode in [LiveDecodeMode.software, LiveDecodeMode.untouched]) {
          final guard = guardWithCache(3.2)
            ..prepare(channel, mode)
            ..armForOpen(player, onStuck: stuck.add);
          expect(guard.isWatching, isFalse);
        }
        // An open nothing was prepared for is not watched either.
        final unprepared = guardWithCache(3.2)..armForOpen(player, onStuck: stuck.add);
        expect(unprepared.isWatching, isFalse);
        player.load();
        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
      });
    });

    test('a newer open ends the watch on the one before it', () {
      fakeAsync((async) {
        final first = <LiveTvChannel>[];
        final second = <LiveTvChannel>[];
        final other = LiveTvChannel(key: 'iptv:src:zdf', serverId: 'src', title: 'ZDF HD');
        final guard = guardWithCache(3.2)
          ..prepare(channel, LiveDecodeMode.guarded)
          ..armForOpen(player, onStuck: first.add);
        player.load();
        async.elapse(const Duration(seconds: 4));

        guard
          ..prepare(other, LiveDecodeMode.guarded)
          ..armForOpen(player, onStuck: second.add);
        player.load();
        async.elapse(const Duration(seconds: 9));

        expect(first, isEmpty);
        expect(second.map((c) => c.key), [other.key]);
      });
    });

    test('disarm ends the watch', () {
      fakeAsync((async) {
        final stuck = <LiveTvChannel>[];
        final guard = guardWithCache(3.2)
          ..prepare(channel, LiveDecodeMode.guarded)
          ..armForOpen(player, onStuck: stuck.add);
        player.load();
        async.elapse(const Duration(seconds: 3));
        guard.disarm();
        async.elapse(const Duration(seconds: 30));
        expect(stuck, isEmpty);
        expect(guard.isWatching, isFalse);
      });
    });
  });

  group('rememberLiveSoftwareDecode', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
    });

    tearDown(SettingsService.resetForTesting);

    test('remembers a channel once and keeps the newest when the list is full', () async {
      final settings = await SettingsService.getInstance();
      await rememberLiveSoftwareDecode(channel, settings: settings);
      await rememberLiveSoftwareDecode(channel, settings: settings);
      expect(settings.read(PlebzPrefs.liveSoftwareDecodeChannels), [liveSoftwareDecodeKey(channel)]);

      for (var i = 0; i < liveSoftwareDecodeMemoryLimit; i++) {
        await rememberLiveSoftwareDecode(
          LiveTvChannel(key: 'c$i', serverId: 'src'),
          settings: settings,
        );
      }
      final stored = settings.read(PlebzPrefs.liveSoftwareDecodeChannels);
      expect(stored, hasLength(liveSoftwareDecodeMemoryLimit));
      expect(stored, isNot(contains(liveSoftwareDecodeKey(channel))));
      expect(
        stored.last,
        liveSoftwareDecodeKey(LiveTvChannel(key: 'c${liveSoftwareDecodeMemoryLimit - 1}', serverId: 'src')),
      );
    });

    test('channels with the same key on two sources are remembered apart', () async {
      final settings = await SettingsService.getInstance();
      await rememberLiveSoftwareDecode(
        LiveTvChannel(key: '101', serverId: 'a'),
        settings: settings,
      );
      expect(
        settings.read(PlebzPrefs.liveSoftwareDecodeChannels),
        isNot(contains(liveSoftwareDecodeKey(LiveTvChannel(key: '101', serverId: 'b')))),
      );
    });

    test('stays on this device: a settings backup does not carry it', () {
      expect(PlebzPrefs.resetAndPortable, isNot(contains(PlebzPrefs.liveSoftwareDecodeChannels)));
      expect(PlebzPrefs.portableOnly, isNot(contains(PlebzPrefs.liveSoftwareDecodeChannels)));
    });
  });
}
