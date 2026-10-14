import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/providers/playback_state_provider.dart';
import 'package:plezy/services/playback_coordinator.dart';
import 'package:plezy/screens/video_player_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/video_player_navigation.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/media_items.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/watch_together_fakes.dart';

/// Plebz (the user's call, 2026-10-14): a stray Back ended films, so the
/// remote's Back leaves the player only when pressed twice; the first puts a
/// hint on the picture.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    VideoPlayerScreenState.backAgainToExit = true;
  });
  tearDown(() => VideoPlayerScreenState.backAgainToExit = false);

  testWidgets('one Back leaves a hint, a second one within the window leaves', (tester) async {
    final player = _TouchExitPlayer();
    final screen = await _pushHeldPlayer(tester, player);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(screen.key.currentState, isNotNull, reason: 'one Back is not enough');
    expect(player.pauseCalls, 0);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(screen.key.currentState, isNull, reason: 'the second Back leaves');
    expect(find.text('Browse'), findsOneWidget);
  });

  testWidgets('a second Back after the window only gives the hint again', (tester) async {
    final player = _TouchExitPlayer();
    final screen = await _pushHeldPlayer(tester, player);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(screen.key.currentState, isNotNull);
  });
}

class _TouchExitPlayer extends FakeSyncPlayer {
  _TouchExitPlayer() : super(playing: true);

  final pauseGate = Completer<void>();
  int pauseCalls = 0;

  @override
  Future<void> abandonAudioFocus() async {}

  @override
  Future<void> pause() async {
    pauseCalls++;
    await pauseGate.future;
  }
}

/// Mounts a player route over a `Browse` root with startup held by music
/// arbitration and [player] already installed.
///
/// A second `VideoPlayerScreen` in this isolate never reaches `initialize` -
/// it inherits the predecessor's native-channel release, which no longer
/// settles once that test's clock is gone (see `test_helpers/hdr_startup.dart`).
/// The route-exit path does not need startup at all, and holding it also keeps
/// cleanup pending so the navigation budget governs the exit.
Future<({GlobalKey<VideoPlayerScreenState> key, GlobalKey<NavigatorState> navigator})> _pushHeldPlayer(
  WidgetTester tester,
  _TouchExitPlayer player,
) async {
  final key = GlobalKey<VideoPlayerScreenState>();
  final navigator = GlobalKey<NavigatorState>();
  final initializationHold = Completer<void>();
  Future<void> holdInitialization() => initializationHold.future;
  PlaybackCoordinator.instance.registerMusicSession(stopAndDispose: holdInitialization);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    PlaybackCoordinator.instance.unregisterMusicSession(holdInitialization);
    if (!player.pauseGate.isCompleted) player.pauseGate.complete();
    if (!initializationHold.isCompleted) initializationHold.complete();
    await tester.pump();
  });
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => PlaybackStateProvider(),
      child: MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Browse')),
      ),
    ),
  );
  unawaited(
    VideoPlayerRoute(
      builder: (_) => VideoPlayerScreen(key: key, metadata: testMediaItem(), isOffline: true),
    ).push(navigator.currentState!),
  );
  await tester.pump();
  key.currentState!.player = player;
  return (key: key, navigator: navigator);
}
