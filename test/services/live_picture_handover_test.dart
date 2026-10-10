import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/live_tv_support.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/mpv/player/video_rect_support.dart';
import 'package:plezy/services/iptv/iptv_live_tv_source.dart';
import 'package:plezy/services/live_picture_handover.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/prefs.dart';

class _FakePlayer implements Player {
  bool _disposed = false;

  @override
  bool get disposed => _disposed;

  @override
  Future<void> dispose({bool preserveDisplayMode = false}) async => _disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A player whose picture can leave its texture, as both Android backends' can.
class _MovablePlayer extends _FakePlayer implements VideoOutputHandover {
  @override
  bool get rendersToTexture => true;
}

/// A player whose window surface sits in a box behind the app.
class _PlanePlayer extends _FakePlayer implements VideoOutputHandover, VideoViewportTarget {
  @override
  bool get rendersToTexture => false;

  @override
  bool get followsVideoRect => true;

  @override
  set videoRectDriven(bool value) {}
}

class _ServerSession implements LiveTvPlaybackSession {
  bool discarded = false;

  @override
  Future<void> discard() async => discarded = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

IptvPlaybackSession _iptvSession() =>
    IptvPlaybackSession(variants: const [(url: 'http://provider.test/live/1.ts', headers: {}, label: 'Das Erste HD')]);

final _channel = LiveTvChannel(key: 'iptv-1', identifier: 'das-erste', callSign: 'Das Erste HD');

LivePictureHandover _picture(Player player, [LiveTvPlaybackSession? session]) =>
    LivePictureHandover(player: player, session: session ?? _iptvSession(), channel: _channel);

void main() {
  late SettingsService settings;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    settings = await SettingsService.getInstance();
  });

  tearDown(() {
    LivePictureReturn.instance.take();
    SettingsService.resetForTesting();
  });

  group('enabledIn', () {
    test('is on by default, with the live frame-rate match off', () async {
      expect(settings.read(SettingsService.liveTvSeamlessFullscreen), isTrue);
      expect(settings.read(SettingsService.matchContentFrameRateLiveTv), isFalse);
      expect(LivePictureHandover.enabledIn(settings, isAndroid: true), isTrue);

      await settings.write(SettingsService.liveTvSeamlessFullscreen, false);
      expect(LivePictureHandover.enabledIn(settings, isAndroid: true), isFalse);
    });

    test('reads off for a viewer who turned the live frame-rate match or live tunnelling on', () async {
      await settings.write(SettingsService.matchContentFrameRateLiveTv, true);
      expect(settings.read(SettingsService.liveTvSeamlessFullscreen), isFalse);

      await settings.write(SettingsService.matchContentFrameRateLiveTv, false);
      await settings.write(SettingsService.tunneledPlaybackLiveTv, true);
      expect(settings.read(SettingsService.liveTvSeamlessFullscreen), isFalse);

      // Their own choice stands.
      await settings.write(SettingsService.liveTvSeamlessFullscreen, true);
      expect(settings.read(SettingsService.liveTvSeamlessFullscreen), isTrue);
    });

    test('on Android with nothing that switches the display, it is on', () async {
      await settings.write(SettingsService.liveTvSeamlessFullscreen, true);

      expect(LivePictureHandover.enabledIn(settings, isAndroid: true), isTrue);
      expect(LivePictureHandover.enabledIn(settings, isAndroid: false), isFalse);
    });

    test('a live frame-rate match stops it, until the switch turns that off', () async {
      await settings.write(SettingsService.liveTvSeamlessFullscreen, true);
      await settings.write(SettingsService.matchContentFrameRate, true);
      await settings.write(SettingsService.matchContentFrameRateLiveTv, true);

      expect(LivePictureHandover.enabledIn(settings, isAndroid: true), isFalse);

      await LivePictureHandover.turnOffWhatInterrupts(settings);

      expect(settings.read(SettingsService.matchContentFrameRateLiveTv), isFalse);
      expect(settings.read(SettingsService.matchContentFrameRate), isTrue, reason: 'films keep theirs');
      expect(LivePictureHandover.enabledIn(settings, isAndroid: true), isTrue);
    });

    test('live tunnelling stops it on ExoPlayer only', () async {
      await settings.write(SettingsService.liveTvSeamlessFullscreen, true);
      await settings.write(SettingsService.tunneledPlaybackLiveTv, true);

      expect(LivePictureHandover.enabledIn(settings, isAndroid: true), isTrue, reason: 'mpv does not tunnel');

      await settings.write(SettingsService.useExoPlayer, true);
      expect(LivePictureHandover.enabledIn(settings, isAndroid: true), isFalse);

      await LivePictureHandover.turnOffWhatInterrupts(settings);
      expect(settings.read(SettingsService.tunneledPlayback), isTrue, reason: 'films keep theirs');
      expect(LivePictureHandover.enabledIn(settings, isAndroid: true), isTrue);
    });
  });

  group('the player IPTV plays on', () {
    test('follows the main choice until it is given one of its own', () async {
      expect(settings.useExoPlayerFor(iptv: true), isFalse);
      await settings.write(SettingsService.useExoPlayer, true);
      expect(settings.useExoPlayerFor(iptv: true), isTrue);
      expect(settings.useExoPlayerFor(iptv: false), isTrue);

      await settings.write(SettingsService.iptvPlayerBackend, IptvPlayerChoice.mpv);
      expect(settings.useExoPlayerFor(iptv: true), isFalse);
      expect(settings.useExoPlayerFor(iptv: false), isTrue, reason: 'films and shows keep the main choice');

      await settings.write(SettingsService.useExoPlayer, false);
      await settings.write(SettingsService.iptvPlayerBackend, IptvPlayerChoice.exoPlayer);
      expect(settings.useExoPlayerFor(iptv: true), isTrue);
      expect(settings.useExoPlayerFor(iptv: false), isFalse);
    });

    test("live tunnelling stops the hand-over when IPTV plays on ExoPlayer, whatever films use", () async {
      await settings.write(SettingsService.liveTvSeamlessFullscreen, true);
      await settings.write(SettingsService.tunneledPlaybackLiveTv, true);
      await settings.write(SettingsService.iptvPlayerBackend, IptvPlayerChoice.exoPlayer);

      expect(LivePictureHandover.enabledIn(settings, isAndroid: true), isFalse);
    });
  });

  group('the video plane', () {
    test('a player is on the plane only when it follows the video rect', () {
      expect(LivePictureHandover.isOnPlane(_MovablePlayer()), isFalse);
      expect(LivePictureHandover.isOnPlane(_PlanePlayer()), isTrue);
    });
  });

  group('canMove', () {
    test('an IPTV stream on a player that can leave its texture', () {
      expect(LivePictureHandover.canMove(_MovablePlayer(), _iptvSession()), isTrue);
    });

    test('not a server session, not a player without the move, not a disposed one', () async {
      expect(LivePictureHandover.canMove(_MovablePlayer(), _ServerSession()), isFalse);
      expect(LivePictureHandover.canMove(_FakePlayer(), _iptvSession()), isFalse);
      final gone = _MovablePlayer();
      await gone.dispose();
      expect(LivePictureHandover.canMove(gone, _iptvSession()), isFalse);
    });
  });

  group('LivePictureReturn', () {
    test('the guide takes the picture up as it was left, once', () {
      final player = _MovablePlayer();
      final picture = _picture(player);
      var notified = 0;
      void listener() => notified++;
      LivePictureReturn.instance.addListener(listener);
      addTearDown(() => LivePictureReturn.instance.removeListener(listener));

      LivePictureReturn.instance.leave(picture);

      expect(notified, 1);
      expect(LivePictureReturn.instance.take(), same(picture));
      expect(LivePictureReturn.instance.take(), isNull);
      expect(player.disposed, isFalse);
    });

    test('a picture nobody takes is stopped, player and session', () {
      fakeAsync((async) {
        final player = _MovablePlayer();
        final session = _ServerSession();
        LivePictureReturn.instance.leave(_picture(player, session));

        async.elapse(const Duration(seconds: 4));
        expect(player.disposed, isFalse);

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(LivePictureReturn.instance.hasPicture, isFalse);
        expect(session.discarded, isTrue);
        expect(player.disposed, isTrue);
      });
    });

    test('a newer picture replaces one still waiting, which is stopped', () async {
      final first = _MovablePlayer();
      final second = _MovablePlayer();
      LivePictureReturn.instance.leave(_picture(first));
      LivePictureReturn.instance.leave(_picture(second));
      await Future<void>.delayed(Duration.zero);

      expect(first.disposed, isTrue);
      expect(LivePictureReturn.instance.take()?.player, same(second));
      expect(second.disposed, isFalse);
    });
  });
}
