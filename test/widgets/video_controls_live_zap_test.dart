import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:plezy/database/app_database.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/focus/remote_keys.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/livetv_capture_buffer.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/providers/playback_state_provider.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/video_volume_controller.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/watch_together/providers/watch_together_provider.dart';
import 'package:plezy/widgets/video_controls/player_chrome_controller.dart';
import 'package:plezy/widgets/video_controls/video_controls.dart';
import 'package:plezy/widgets/video_controls/widgets/live_channel_strip.dart';
import 'package:plezy/widgets/video_controls/widgets/player_toast_indicator.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/theme.dart';

/// The remote's directional keys belong to the channel while live TV is
/// playing: nothing to seek in without a server recording, so UP/DOWN zap and
/// LEFT opens the channel list. OK is what raises the controls.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _LivePlayer player;
  late PlayerChromeController chrome;
  late PlayerToastController toast;
  late VideoVolumeController volume;
  late PlaybackStateProvider playbackState;
  late WatchTogetherProvider watchTogether;
  late AppDatabase database;
  late ValueNotifier<bool> hasFirstFrame;
  late SettingsService settings;
  var nextChannel = 0;
  var previousChannel = 0;
  var toggles = 0;
  final selectedChannels = <int>[];

  final channels = [
    for (var i = 0; i < 5; i++)
      LiveTvChannel(key: 'iptv:src:$i', title: 'Channel $i', number: '${i + 1}', serverId: 'src'),
  ];

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    settings = await SettingsService.getInstance();
    await settings.write(SettingsService.videoPlayerNavigationEnabled, true);

    TvDetectionService.debugSetAppleTVOverride(false);
    PlatformDetector.debugSetIsDesktopOSOverride(true);

    database = AppDatabase.forTesting(NativeDatabase.memory());
    player = _LivePlayer();
    chrome = PlayerChromeController(initiallyVisible: false);
    toast = PlayerToastController();
    volume = VideoVolumeController(player: player, settings: settings, initialVolume: 100);
    playbackState = PlaybackStateProvider();
    watchTogether = WatchTogetherProvider();
    hasFirstFrame = ValueNotifier<bool>(true);
    nextChannel = 0;
    previousChannel = 0;
    toggles = 0;
    selectedChannels.clear();
  });

  tearDown(() async {
    TvDetectionService.debugSetAppleTVOverride(null);
    PlatformDetector.debugSetIsDesktopOSOverride(null);
    hasFirstFrame.dispose();
    volume.dispose();
    playbackState.dispose();
    watchTogether.dispose();
    chrome.dispose();
    toast.dispose();
    await player.close();
    await database.close();
  });

  Widget shell(Widget child) => InputModeTracker(
    child: MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: database),
        ChangeNotifierProvider<PlaybackStateProvider>.value(value: playbackState),
        ChangeNotifierProvider<WatchTogetherProvider>.value(value: watchTogether),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows, extensions: const [testMonoTokens]),
        home: Scaffold(body: SizedBox(width: 1280, height: 720, child: child)),
      ),
    ),
  );

  Future<void> pumpPlayer(
    WidgetTester tester, {
    bool isLive = true,
    CaptureBuffer? captureBuffer,
    bool isAtLiveEdge = true,
    List<LiveTvChannel>? liveChannels,
    int liveChannelIndex = 2,
    VoidCallback? onBack,
  }) async {
    await tester.pumpWidget(
      shell(
        PlexVideoControls(
          player: player,
          volumeController: volume,
          metadata: testMediaItem(id: 'live-zap'),
          toastController: toast,
          chromeController: chrome,
          hasFirstFrame: hasFirstFrame,
          canNavigateMediaItems: false,
          isLive: isLive,
          captureBuffer: captureBuffer,
          // What the player always supplies for a live session; without it the
          // time-shift bar has no way to place a position.
          liveEpochForPosition: isLive ? (position) => 1000 + position.inSeconds : null,
          isAtLiveEdge: isAtLiveEdge,
          liveChannels: liveChannels ?? channels,
          liveChannelIndex: liveChannelIndex,
          onLiveChannelSelected: selectedChannels.add,
          onBack: onBack,
          onNext: () => nextChannel++,
          onPrevious: () => previousChannel++,
          onPlayPauseRequested: (_) async => toggles++,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {String? platform}) async {
    if (platform == null) {
      await tester.sendKeyDownEvent(key);
      await tester.pump();
      await tester.sendKeyUpEvent(key);
    } else {
      // The simulator knows no physical key for some remote buttons (Guide);
      // the player reads the logical key alone, so any stands in for it.
      const stand = PhysicalKeyboardKey.f24;
      await tester.sendKeyDownEvent(key, platform: platform, physicalKey: stand);
      await tester.pump();
      await tester.sendKeyUpEvent(key, platform: platform, physicalKey: stand);
    }
    await tester.pumpAndSettle();
  }

  void endTest(WidgetTester tester) => chrome.cancelAutoHide();

  testWidgets('down and up zap a channel each, without raising the controls', (tester) async {
    await pumpPlayer(tester);

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(nextChannel, 1, reason: 'down goes down the channel list');
    expect(chrome.controlsVisible, isFalse, reason: 'zapping is not a request for the OSD');

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(previousChannel, 1);
    expect(chrome.controlsVisible, isFalse);

    endTest(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the channel keys stay quiet until they are switched on', (tester) async {
    await pumpPlayer(tester);

    await press(tester, LogicalKeyboardKey.channelDown);
    await press(tester, LogicalKeyboardKey.channelUp);

    // Most remotes have no such keys, and some devices keep them for their own
    // tuner, so nothing happens until the viewer says otherwise.
    expect(nextChannel, 0);
    expect(previousChannel, 0);

    endTest(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switched on, P+ and P- zap with the controls down', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.zapWithChannelKeys, true);
    await pumpPlayer(tester);

    await press(tester, LogicalKeyboardKey.channelDown);
    expect(nextChannel, 1, reason: 'P- goes down the channel list');
    expect(chrome.controlsVisible, isFalse);

    await press(tester, LogicalKeyboardKey.channelUp);
    expect(previousChannel, 1);

    endTest(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switched on, they zap with the controls up as well', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.zapWithChannelKeys, true);
    await pumpPlayer(tester);

    // The arrow keys only zap while the chrome is down, because up there they
    // belong to the controls. A dedicated key means nothing else anywhere.
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(chrome.controlsVisible, isTrue, reason: 'otherwise this test proves nothing about the chrome being up');

    final zapsSoFar = nextChannel;
    await press(tester, LogicalKeyboardKey.channelDown);

    expect(nextChannel, zapsSoFar + 1);

    endTest(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('left opens the channel list on a stream that cannot be rewound', (tester) async {
    await pumpPlayer(tester);

    await press(tester, LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(chrome.controlsVisible, isTrue);
    expect(find.byType(LiveChannelStrip), findsOneWidget);
    // The cell and the info line above it both name it.
    expect(find.text('3  Channel 2'), findsWidgets, reason: 'it opens on the channel that is playing');

    endTest(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('back closes a strip opened from the picture without leaving the controls up', (tester) async {
    await pumpPlayer(tester);

    await press(tester, LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.byType(LiveChannelStrip), findsOneWidget);
    // The chrome is up only because the strip lives in its panel.
    expect(chrome.controlsVisible, isTrue);

    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(LiveChannelStrip), findsNothing);
    expect(
      chrome.controlsVisible,
      isFalse,
      reason: 'one Back goes back to the picture; a second one would be the viewer paying for our panel',
    );

    endTest(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a strip opened from the chrome still closes to the chrome', (tester) async {
    await pumpPlayer(tester);

    // The controls first, then the strip out of them: the viewer asked for
    // both, so Back gives the controls back.
    await press(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(chrome.controlsVisible, isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byType(LiveChannelStrip), findsOneWidget);

    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(LiveChannelStrip), findsNothing);
    expect(chrome.controlsVisible, isTrue);

    endTest(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a rewound session keeps left and right for its time-shift', (tester) async {
    // Behind the live edge the viewer is working in the timeline, and LEFT is
    // how they move in it.
    await pumpPlayer(
      tester,
      captureBuffer: CaptureBuffer(startedAt: 1000, seekStartSeconds: 0, seekEndSeconds: 600),
      isAtLiveEdge: false,
    );

    await press(tester, LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(find.byType(LiveChannelStrip), findsNothing);

    endTest(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a channel that could be rewound still opens the list while it is live', (tester) async {
    // The regression this exists for: an IPTV station whose archive sits on
    // another copy of itself gained a seekable window, and that alone took
    // the channel list away from every one of them.
    await pumpPlayer(tester, captureBuffer: CaptureBuffer(startedAt: 1000, seekStartSeconds: 0, seekEndSeconds: 600));

    await press(tester, LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(find.byType(LiveChannelStrip), findsOneWidget);

    endTest(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('OK raises the controls and leaves a live stream running', (tester) async {
    // Pausing a stream nothing is recording only drops the viewer behind the
    // live edge, with no way back to it.
    await pumpPlayer(tester);

    await press(tester, LogicalKeyboardKey.select);

    expect(chrome.controlsVisible, isTrue);
    expect(toggles, 0);

    endTest(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a single channel leaves the directional keys alone', (tester) async {
    await pumpPlayer(tester, liveChannels: [channels.first]);

    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(nextChannel, 0);
    expect(chrome.controlsVisible, isTrue, reason: 'nothing to zap, so down is the show-me-the-controls gesture');

    endTest(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a film is untouched by any of it', (tester) async {
    await pumpPlayer(tester, isLive: false);

    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(nextChannel, 0, reason: 'down must not skip to the next episode');
    expect(chrome.controlsVisible, isTrue);

    endTest(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('the remote\'s extra keys (Plebz)', () {
    testWidgets('a typed channel number tunes that channel after a pause', (tester) async {
      await pumpPlayer(tester);

      await press(tester, LogicalKeyboardKey.digit4, platform: 'android');
      expect(selectedChannels, isEmpty, reason: 'a second digit may follow');
      await tester.pump(const Duration(milliseconds: 1600));

      expect(selectedChannels, [3], reason: 'channel number 4 is the fourth in the list');
      await tester.pump(const Duration(seconds: 2));
      endTest(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a number no channel has tunes nothing', (tester) async {
      await pumpPlayer(tester);

      await press(tester, LogicalKeyboardKey.digit9, platform: 'android');
      await press(tester, LogicalKeyboardKey.digit9, platform: 'android');
      await tester.pump(const Duration(milliseconds: 1600));

      expect(selectedChannels, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      endTest(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the last-channel key goes back to the channel before', (tester) async {
      await pumpPlayer(tester);
      await press(tester, LogicalKeyboardKey.info, platform: 'android');
      await press(tester, LogicalKeyboardKey.info, platform: 'android');
      await pumpPlayer(tester, liveChannelIndex: 4);

      await press(tester, LogicalKeyboardKey.mediaLast, platform: 'android');

      expect(selectedChannels, [2]);
      endTest(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the guide key opens the channel list', (tester) async {
      await pumpPlayer(tester);

      await press(tester, LogicalKeyboardKey.guide, platform: 'android');

      expect(find.byType(LiveChannelStrip), findsOneWidget);
      endTest(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('info raises the controls and lowers them again', (tester) async {
      await pumpPlayer(tester);

      await press(tester, LogicalKeyboardKey.info, platform: 'android');
      expect(chrome.controlsVisible, isTrue);
      await press(tester, LogicalKeyboardKey.info, platform: 'android');
      expect(chrome.controlsVisible, isFalse);

      endTest(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a colour key does what it is set to: here, the channel list', (tester) async {
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.remoteBlueButton, RemoteButtonFunction.channelList);
      await pumpPlayer(tester);

      await press(tester, LogicalKeyboardKey.colorF3Blue, platform: 'android');

      expect(find.byType(LiveChannelStrip), findsOneWidget);
      endTest(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a colour key set to nothing does nothing', (tester) async {
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.remoteBlueButton, RemoteButtonFunction.none);
      await pumpPlayer(tester);

      await press(tester, LogicalKeyboardKey.colorF3Blue, platform: 'android');

      expect(chrome.controlsVisible, isFalse);
      endTest(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('stop leaves the player', (tester) async {
      var left = 0;
      await pumpPlayer(tester, onBack: () => left++);

      await press(tester, LogicalKeyboardKey.mediaStop, platform: 'android');

      expect(left, 1);
      endTest(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

class _LivePlayer implements Player {
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();

  Future<void> close() => _positionController.close();

  @override
  String get playerType => 'mpv';

  @override
  PlayerState get state => const PlayerState(playing: true, position: Duration.zero, duration: Duration.zero);

  @override
  PlayerStreams get streams => PlayerStreams(
    playing: const Stream<bool>.empty(),
    completed: const Stream<bool>.empty(),
    buffering: const Stream<bool>.empty(),
    position: _positionController.stream,
    duration: const Stream<Duration>.empty(),
    seekable: const Stream<bool>.empty(),
    buffer: const Stream<Duration>.empty(),
    volume: const Stream<double>.empty(),
    rate: const Stream<double>.empty(),
    tracks: const Stream<Tracks>.empty(),
    track: const Stream<TrackSelection>.empty(),
    log: const Stream<PlayerLog>.empty(),
    error: const Stream<PlayerError>.empty(),
    audioDevice: const Stream<AudioDevice>.empty(),
    audioDevices: const Stream<List<AudioDevice>>.empty(),
    bufferRanges: const Stream<List<BufferRange>>.empty(),
    playbackRestart: const Stream<void>.empty(),
    backendSwitched: const Stream<void>.empty(),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
