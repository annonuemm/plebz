import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/playback_state_provider.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/screens/video_player/widgets/player_prompt_overlays.dart';
import 'package:plezy/services/pip_service.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/optimized_media_image.dart';
import 'package:plezy/widgets/video_controls/player_chrome_controller.dart';
import 'package:provider/provider.dart';
import '../../test_helpers/media_items.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

/// The overlays read the countdown through a `ValueListenable` so the
/// per-second tick no longer rebuilds the whole player chrome. Tests own the
/// notifier, matching production where the screen state owns and disposes it.
ValueNotifier<int> _countdown([int value = -1]) {
  final notifier = ValueNotifier<int>(value);
  addTearDown(notifier.dispose);
  return notifier;
}

void main() {
  testWidgets('play next prompt tracks chrome visibility for vertical position', (tester) async {
    PipService().isPipActive.value = false;
    final chromeController = PlayerChromeController();
    final cancelFocusNode = FocusNode(debugLabel: 'TestCancel');
    final confirmFocusNode = FocusNode(debugLabel: 'TestConfirm');
    addTearDown(chromeController.dispose);
    addTearDown(cancelFocusNode.dispose);
    addTearDown(confirmFocusNode.dispose);

    await tester.pumpWidget(
      _wrapPrompt(
        VideoPlayerPlayNextOverlay(
          visible: true,
          nextEpisode: _episode(),
          autoPlayCountdown: _countdown(),
          cancelFocusNode: cancelFocusNode,
          confirmFocusNode: confirmFocusNode,
          chromeController: chromeController,
          onCancel: () {},
          onPlayNext: () {},
        ),
      ),
    );

    expect(_promptPosition(tester).bottom, 100);

    chromeController.hide();
    await tester.pump();
    expect(_promptPosition(tester).bottom, 24);
  });

  testWidgets('hovering play next prompt holds chrome visible and stable', (tester) async {
    PipService().isPipActive.value = false;
    final chromeController = PlayerChromeController();
    final cancelFocusNode = FocusNode(debugLabel: 'TestCancel');
    final confirmFocusNode = FocusNode(debugLabel: 'TestConfirm');
    addTearDown(chromeController.dispose);
    addTearDown(cancelFocusNode.dispose);
    addTearDown(confirmFocusNode.dispose);

    chromeController.hide();

    await tester.pumpWidget(
      _wrapPrompt(
        VideoPlayerPlayNextOverlay(
          visible: true,
          nextEpisode: _episode(),
          autoPlayCountdown: _countdown(),
          cancelFocusNode: cancelFocusNode,
          confirmFocusNode: confirmFocusNode,
          chromeController: chromeController,
          onCancel: () {},
          onPlayNext: () {},
        ),
      ),
    );

    expect(_promptPosition(tester).bottom, 24);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('Cancel')));
    await tester.pump();

    expect(chromeController.controlsVisible, isTrue);
    expect(chromeController.isHeld(PlayerChromeHold.promptInteraction), isTrue);
    expect(_promptPosition(tester).bottom, 100);
    expect(chromeController.hide(), isFalse);
    expect(_promptPosition(tester).bottom, 100);
  });

  testWidgets('focused play next prompt holds chrome visible', (tester) async {
    PipService().isPipActive.value = false;
    final chromeController = PlayerChromeController();
    final cancelFocusNode = FocusNode(debugLabel: 'TestCancel');
    final confirmFocusNode = FocusNode(debugLabel: 'TestConfirm');
    addTearDown(chromeController.dispose);
    addTearDown(cancelFocusNode.dispose);
    addTearDown(confirmFocusNode.dispose);

    await tester.pumpWidget(
      _wrapPrompt(
        VideoPlayerPlayNextOverlay(
          visible: true,
          nextEpisode: _episode(),
          autoPlayCountdown: _countdown(),
          cancelFocusNode: cancelFocusNode,
          confirmFocusNode: confirmFocusNode,
          chromeController: chromeController,
          onCancel: () {},
          onPlayNext: () {},
        ),
      ),
    );

    confirmFocusNode.requestFocus();
    await tester.pump();

    expect(chromeController.isHeld(PlayerChromeHold.promptInteraction), isTrue);
    expect(chromeController.hide(), isFalse);
  });

  testWidgets('removing a held prompt releases hold without notifying during dispose', (tester) async {
    PipService().isPipActive.value = false;
    final chromeController = PlayerChromeController();
    final cancelFocusNode = FocusNode(debugLabel: 'TestCancel');
    final confirmFocusNode = FocusNode(debugLabel: 'TestConfirm');
    addTearDown(chromeController.dispose);
    addTearDown(cancelFocusNode.dispose);
    addTearDown(confirmFocusNode.dispose);

    await tester.pumpWidget(
      _wrapPrompt(
        VideoPlayerPlayNextOverlay(
          visible: true,
          nextEpisode: _episode(),
          autoPlayCountdown: _countdown(),
          cancelFocusNode: cancelFocusNode,
          confirmFocusNode: confirmFocusNode,
          chromeController: chromeController,
          onCancel: () {},
          onPlayNext: () {},
        ),
      ),
    );

    chromeController.hold(PlayerChromeHold.promptInteraction);
    var notifications = 0;
    chromeController.addListener(() => notifications++);

    await tester.pumpWidget(_wrapPrompt(const SizedBox.shrink()));

    expect(chromeController.isHeld(PlayerChromeHold.promptInteraction), isFalse);
    expect(notifications, 0);
  });

  testWidgets('the zap banner names the channel and what is on it, then fades', (tester) async {
    final visible = ValueNotifier<bool>(false);
    addTearDown(visible.dispose);

    await tester.pumpWidget(
      _wrapPrompt(VideoPlayerZapBanner(visible: visible, channelName: 'Das Erste HD', programTitle: 'Tagesschau')),
    );

    // Built but transparent until a zap announces one; the opacity is what
    // fades, so the text stays in the tree throughout.
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0);

    visible.value = true;
    await tester.pump();

    // The name alone, no channel number, in line with the programme below.
    expect(find.text('Das Erste HD'), findsOneWidget);
    expect(find.text('Tagesschau'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Das Erste HD')).dx, tester.getTopLeft(find.text('Tagesschau')).dx);
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
  });

  testWidgets('under glass the zap banner is a pane of glass; elsewhere it keeps its black box', (tester) async {
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);
    Widget banner() => VideoPlayerZapBanner(visible: visible, channelName: 'Das Erste HD', programTitle: 'Tagesschau');

    await tester.pumpWidget(_wrapPrompt(banner(), theme: monoTheme(dark: true, variant: AppThemeVariant.glas)));
    expect(find.ancestor(of: find.text('Das Erste HD'), matching: find.byType(OckerGlass)), findsOneWidget);
    expect(find.ancestor(of: find.text('Tagesschau'), matching: find.byType(OckerGlass)), findsOneWidget);

    await tester.pumpWidget(_wrapPrompt(banner(), theme: monoTheme(dark: true)));
    // The app animates from one theme to the next.
    await tester.pumpAndSettle();
    expect(find.byType(OckerGlass), findsNothing);
    expect(find.text('Das Erste HD'), findsOneWidget);
  });

  testWidgets('a channel without a guide entry is announced on its own', (tester) async {
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);

    await tester.pumpWidget(
      _wrapPrompt(VideoPlayerZapBanner(visible: visible, channelName: 'Kein EPG', programTitle: null)),
    );

    expect(find.text('Kein EPG'), findsOneWidget);
  });

  testWidgets('the buffering spinner announces loading until the first frame renders', (tester) async {
    PipService().isPipActive.value = false;
    final isBuffering = ValueNotifier<bool>(false);
    final hasFirstFrame = ValueNotifier<bool>(false);
    final isExiting = ValueNotifier<bool>(false);
    final isSwitchingChannel = ValueNotifier<bool>(false);
    addTearDown(isBuffering.dispose);
    addTearDown(hasFirstFrame.dispose);
    addTearDown(isExiting.dispose);
    addTearDown(isSwitchingChannel.dispose);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _wrapPrompt(
        VideoPlayerBufferingOverlay(
          isBuffering: isBuffering,
          hasFirstFrame: hasFirstFrame,
          isExiting: isExiting,
          isSwitchingChannel: isSwitchingChannel,
        ),
      ),
    );

    // The TV player no longer raises its chrome on startup (#1765), so this
    // label is what tells "the player is still waiting for its first frame"
    // apart from "it has stopped waiting" — the readiness gate the Maestro TV
    // flows use in place of the Pause button.
    expect(find.bySemanticsLabel('Loading video'), findsOneWidget);

    hasFirstFrame.value = true;
    await tester.pump();
    expect(find.bySemanticsLabel('Loading video'), findsNothing);

    isBuffering.value = true;
    await tester.pump();
    expect(find.bySemanticsLabel('Loading video'), findsOneWidget, reason: 'a mid-playback stall loads again');

    // A channel switch keeps the outgoing channel's last frame on screen and
    // stays quiet — even while the new stream buffers — until it runs long;
    // then the spinner speaks for a picture that is deliberately not moving.
    isBuffering.value = false;
    await tester.pump();
    expect(find.bySemanticsLabel('Loading video'), findsNothing);

    isSwitchingChannel.value = true;
    isBuffering.value = true;
    await tester.pump();
    expect(find.bySemanticsLabel('Loading video'), findsNothing, reason: 'a zap is quiet');

    await tester.pump(VideoPlayerBufferingOverlay.switchSpinnerDelay);
    expect(find.bySemanticsLabel('Loading video'), findsOneWidget, reason: 'a slow switch is not left silent');

    isSwitchingChannel.value = false;
    isBuffering.value = false;
    await tester.pump();
    expect(find.bySemanticsLabel('Loading video'), findsNothing);

    // The next zap starts quiet again.
    isSwitchingChannel.value = true;
    await tester.pump();
    expect(find.bySemanticsLabel('Loading video'), findsNothing);
    isSwitchingChannel.value = false;
    await tester.pump();

    semantics.dispose();
  });

  // The whole point of moving the countdown to a ValueListenable: the digit
  // updates without the parent being rebuilt. Previously a 1 Hz timer called a
  // root setState on the player screen, which re-created PlexVideoControls
  // (~50 props) and rebuilt the entire chrome once per second.
  testWidgets('play next countdown digit updates without rebuilding the parent', (tester) async {
    PipService().isPipActive.value = false;
    final chromeController = PlayerChromeController();
    final cancelFocusNode = FocusNode(debugLabel: 'TestCancel');
    final confirmFocusNode = FocusNode(debugLabel: 'TestConfirm');
    final countdown = ValueNotifier<int>(5);
    addTearDown(chromeController.dispose);
    addTearDown(cancelFocusNode.dispose);
    addTearDown(confirmFocusNode.dispose);
    addTearDown(countdown.dispose);

    var parentBuilds = 0;
    await tester.pumpWidget(
      _wrapPrompt(
        Builder(
          builder: (context) {
            parentBuilds++;
            return VideoPlayerPlayNextOverlay(
              visible: true,
              nextEpisode: _episode(),
              autoPlayCountdown: countdown,
              cancelFocusNode: cancelFocusNode,
              confirmFocusNode: confirmFocusNode,
              chromeController: chromeController,
              onCancel: () {},
              onPlayNext: () {},
            );
          },
        ),
      ),
    );

    expect(find.text('5'), findsOneWidget);
    final buildsAfterMount = parentBuilds;

    countdown.value = 4;
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
    expect(find.text('5'), findsNothing);

    countdown.value = 3;
    await tester.pump();
    expect(find.text('3'), findsOneWidget);

    expect(parentBuilds, buildsAfterMount, reason: 'the countdown must not rebuild anything above the overlay');
  });

  // -1 is the "no automatic advance" sentinel: the prompt shows its action
  // label instead of a digit, which is the manual play-next case.
  testWidgets('play next prompt shows its label instead of a digit when the countdown is absent', (tester) async {
    PipService().isPipActive.value = false;
    final chromeController = PlayerChromeController();
    final cancelFocusNode = FocusNode(debugLabel: 'TestCancel');
    final confirmFocusNode = FocusNode(debugLabel: 'TestConfirm');
    final countdown = ValueNotifier<int>(2);
    addTearDown(chromeController.dispose);
    addTearDown(cancelFocusNode.dispose);
    addTearDown(confirmFocusNode.dispose);
    addTearDown(countdown.dispose);

    await tester.pumpWidget(
      _wrapPrompt(
        VideoPlayerPlayNextOverlay(
          visible: true,
          nextEpisode: _episode(),
          autoPlayCountdown: countdown,
          cancelFocusNode: cancelFocusNode,
          confirmFocusNode: confirmFocusNode,
          chromeController: chromeController,
          onCancel: () {},
          onPlayNext: () {},
        ),
      ),
    );
    expect(find.text('2'), findsOneWidget);

    countdown.value = -1;
    await tester.pump();
    expect(find.text('-1'), findsNothing);
    expect(find.text('2'), findsNothing);
  });

  // The play-next card paints the next episode's video-frame still behind the
  // text under a scrim (#2166), falling back to the original text-only card
  // when no thumbnail can be served.
  group('next episode thumbnail backdrop', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
    });

    Widget pumpablePrompt(MediaItem episode, {MultiServerProvider? servers}) {
      PipService().isPipActive.value = false;
      final chromeController = PlayerChromeController();
      final cancelFocusNode = FocusNode(debugLabel: 'TestCancel');
      final confirmFocusNode = FocusNode(debugLabel: 'TestConfirm');
      addTearDown(chromeController.dispose);
      addTearDown(cancelFocusNode.dispose);
      addTearDown(confirmFocusNode.dispose);
      return _wrapPrompt(
        VideoPlayerPlayNextOverlay(
          visible: true,
          nextEpisode: episode,
          autoPlayCountdown: _countdown(),
          cancelFocusNode: cancelFocusNode,
          confirmFocusNode: confirmFocusNode,
          chromeController: chromeController,
          onCancel: () {},
          onPlayNext: () {},
        ),
        servers: servers,
      );
    }

    testWidgets('renders the still behind the prompt when a client can serve the thumb', (tester) async {
      final servers = testMultiServer(clients: [_StubThumbClient()]);

      await tester.pumpWidget(pumpablePrompt(_thumbEpisode(), servers: servers.provider));

      expect(find.byType(OptimizedMediaImage), findsOneWidget);
      // Hide-spoilers is off, so the still is not blurred.
      expect(find.byType(ImageFiltered), findsNothing);
      // The text card content is unchanged on top of the backdrop.
      expect(find.text('S1 E2 · Episode 2'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('keeps the text-only card when the episode has no thumb', (tester) async {
      final servers = testMultiServer(clients: [_StubThumbClient()]);

      await tester.pumpWidget(pumpablePrompt(_episode(), servers: servers.provider));

      expect(find.byType(OptimizedMediaImage), findsNothing);
      expect(find.text('S1 E2 · Episode 2'), findsOneWidget);
    });

    testWidgets('keeps the text-only card when nothing could serve the thumb', (tester) async {
      // A thumb path but no registered client and no downloaded artwork:
      // the card must not reserve backdrop space it cannot fill.
      await tester.pumpWidget(pumpablePrompt(_thumbEpisode()));

      expect(find.byType(OptimizedMediaImage), findsNothing);
      expect(find.text('S1 E2 · Episode 2'), findsOneWidget);
    });

    testWidgets('blurs the unwatched still when hide-spoilers is on', (tester) async {
      await SettingsService.instance.write(SettingsService.hideSpoilers, true);
      final servers = testMultiServer(clients: [_StubThumbClient()]);

      await tester.pumpWidget(pumpablePrompt(_thumbEpisode(), servers: servers.provider));

      expect(find.byType(OptimizedMediaImage), findsOneWidget);
      expect(find.byType(ImageFiltered), findsOneWidget);
    });
  });
}

Widget _wrapPrompt(Widget child, {MultiServerProvider? servers, ThemeData? theme}) {
  Widget app = ChangeNotifierProvider(
    create: (_) => PlaybackStateProvider(),
    child: MaterialApp(
      theme: theme,
      home: Scaffold(body: Stack(children: [child])),
    ),
  );
  if (servers != null) {
    app = ChangeNotifierProvider<MultiServerProvider>.value(value: servers, child: app);
  }
  return app;
}

AnimatedPositioned _promptPosition(WidgetTester tester) {
  return tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned));
}

MediaItem _episode() {
  return testMediaItem(
    id: 'episode-2',
    backend: MediaBackend.plex,
    kind: MediaKind.episode,
    title: 'Episode 2',
    parentIndex: 1,
    index: 2,
  );
}

MediaItem _thumbEpisode() {
  return testMediaItem(
    id: 'episode-2',
    backend: MediaBackend.plex,
    kind: MediaKind.episode,
    title: 'Episode 2',
    parentIndex: 1,
    index: 2,
    serverId: 'server-1',
    thumbPath: '/library/metadata/episode-2/thumb/1',
  );
}

/// Registered under `server-1`; deliberately returns an unresolvable image URL
/// so the backdrop exercises the widget path without a network fetch.
class _StubThumbClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('server-1');

  @override
  String thumbnailUrl(String? path, {int? width, int? height, bool cover = true}) => '';

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
