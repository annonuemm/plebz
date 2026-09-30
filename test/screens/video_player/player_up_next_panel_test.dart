import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/screens/video_player/widgets/player_up_next_panel.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/widgets/optimized_media_image.dart';
import 'package:provider/provider.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';
import 'package:plezy/widgets/video_controls/player_chrome_controller.dart';

import '../../test_helpers/media_items.dart';
import '../../test_helpers/multi_server_fixtures.dart';

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  Future<({int played, int closed})> pumpPanel(
    WidgetTester tester, {
    bool visible = true,
    String? thumbPath,
    bool withNeighbour = false,
    AppThemeVariant variant = AppThemeVariant.standard,
  }) async {
    var played = 0;
    var closed = 0;
    final multiServer = testMultiServerProvider(MultiServerManager());
    addTearDown(multiServer.dispose);
    final chrome = PlayerChromeController();
    addTearDown(chrome.dispose);
    final play = FocusNode(debugLabel: 'play');
    final close = FocusNode(debugLabel: 'close');
    addTearDown(play.dispose);
    addTearDown(close.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer)],
          child: MaterialApp(
            theme: monoTheme(dark: true, variant: variant),
            builder: (context, child) => InputModeTracker(child: child!),
            home: Scaffold(
              body: Stack(
                children: [
                  if (withNeighbour)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(onPressed: () {}, child: const Text('neighbour')),
                    ),
                  PlayerUpNextPanel(
                    visible: visible,
                    nextEpisode: testMediaItem(
                      id: 'ep-2',
                      backend: MediaBackend.plex,
                      kind: MediaKind.episode,
                      title: 'Cat in the Bag',
                      grandparentTitle: 'Breaking Bad',
                      summary: 'Walt and Jesse deal with the aftermath.',
                      thumbPath: thumbPath,
                    ),
                    playFocusNode: play,
                    closeFocusNode: close,
                    onPlay: () => played++,
                    onClose: () => closed++,
                    chromeController: chrome,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (played: played, closed: closed);
  }

  testWidgets('names the series, the episode and what it is about', (tester) async {
    await pumpPanel(tester);

    expect(find.text('Breaking Bad'), findsOneWidget);
    expect(find.text('Cat in the Bag'), findsOneWidget);
    expect(find.text('Walt and Jesse deal with the aftermath.'), findsOneWidget);
    expect(find.text(t.videoControls.upNext), findsOneWidget);
  });

  testWidgets('offers the two ways out and nothing else', (tester) async {
    await pumpPanel(tester);

    // Back is the third way, and it is deliberately not a button: it means
    // "let the episode finish".
    expect(find.text(t.common.play), findsOneWidget);
    expect(find.text(t.videoControls.closeUpNext), findsOneWidget);
    expect(find.text(t.common.cancel), findsNothing);
  });

  testWidgets('the episode still sits between its name and the description', (tester) async {
    await pumpPanel(tester, thumbPath: '/library/metadata/2/thumb');

    expect(find.byType(OptimizedMediaImage), findsOneWidget);
  });

  testWidgets('an episode without a still keeps its text', (tester) async {
    await pumpPanel(tester);

    expect(find.byType(OptimizedMediaImage), findsNothing);
    expect(find.text('Walt and Jesse deal with the aftermath.'), findsOneWidget);
  });

  testWidgets('appearing takes the cursor to the play button', (tester) async {
    // The panel is raised while something else holds the focus — in the
    // player that is its own navigation — so it has to claim it, and only
    // once its buttons exist.
    final play = FocusNode(debugLabel: 'play');
    final close = FocusNode(debugLabel: 'close');
    final chrome = PlayerChromeController();
    addTearDown(play.dispose);
    addTearDown(close.dispose);
    addTearDown(chrome.dispose);

    Widget panel({required bool visible}) => TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: PlayerUpNextPanel(
            visible: visible,
            nextEpisode: testMediaItem(
              id: 'ep-2',
              backend: MediaBackend.plex,
              kind: MediaKind.episode,
              title: 'Cat in the Bag',
            ),
            playFocusNode: play,
            closeFocusNode: close,
            onPlay: () {},
            onClose: () {},
            chromeController: chrome,
          ),
        ),
      ),
    );

    await tester.pumpWidget(panel(visible: false));
    await tester.pumpAndSettle();
    expect(play.hasFocus, isFalse);

    await tester.pumpWidget(panel(visible: true));
    await tester.pumpAndSettle();

    expect(play.hasFocus, isTrue, reason: 'the offer is only an offer if the cursor is on it');
  });

  testWidgets('the panel stops the auto-hide without turning the controls on', (tester) async {
    // The auto-hide would otherwise take the controls away after a few
    // seconds of stillness — and the focus with them, leaving an overlay on
    // screen that can no longer be reached.
    final play = FocusNode(debugLabel: 'play');
    final close = FocusNode(debugLabel: 'close');
    final chrome = PlayerChromeController(initiallyVisible: false);
    addTearDown(play.dispose);
    addTearDown(close.dispose);
    addTearDown(chrome.dispose);

    Widget panel({required bool visible}) => TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: PlayerUpNextPanel(
            visible: visible,
            nextEpisode: testMediaItem(id: 'ep-2', backend: MediaBackend.plex, kind: MediaKind.episode, title: 'Next'),
            playFocusNode: play,
            closeFocusNode: close,
            onPlay: () {},
            onClose: () {},
            chromeController: chrome,
          ),
        ),
      ),
    );

    await tester.pumpWidget(panel(visible: false));
    await tester.pumpAndSettle();
    expect(chrome.isHeld(PlayerChromeHold.promptInteraction), isFalse);

    await tester.pumpWidget(panel(visible: true));
    await tester.pumpAndSettle();
    expect(chrome.isHeld(PlayerChromeHold.promptInteraction), isTrue);
    expect(
      chrome.controlsVisible,
      isFalse,
      reason: 'the offer is the panel — the transport controls were not asked for',
    );

    await tester.pumpWidget(panel(visible: false));
    await tester.pumpAndSettle();
    expect(chrome.isHeld(PlayerChromeHold.promptInteraction), isFalse, reason: 'and released again when it goes');

    // Releasing hands the auto-hide back to the chrome, which arms its timer;
    // the test owns the controller, so it stops it here.
    chrome.cancelAutoHide();
  });

  testWidgets('the cursor cannot walk out of the panel', (tester) async {
    // With something focusable beside it — in the player that is the whole
    // control bar — the arrows would otherwise walk out, and the panel has no
    // cursor of its own to come back to.
    await pumpPanel(tester, withNeighbour: true);
    expect(find.text('neighbour'), findsOneWidget);
    final play = tester.widget<PlayerUpNextPanel>(find.byType(PlayerUpNextPanel)).playFocusNode;
    play.requestFocus();
    await tester.pumpAndSettle();

    for (final key in [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowUp]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(play.hasFocus, isTrue, reason: '$key must not leave the panel');
    }

    // Down is the one direction that goes somewhere: the other button.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final close = tester.widget<PlayerUpNextPanel>(find.byType(PlayerUpNextPanel)).closeFocusNode;
    expect(close.hasFocus, isTrue);

    for (final key in [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowDown]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(close.hasFocus, isTrue, reason: '$key must not leave the panel');
    }
  });

  group('looks like the theme it is drawn in', () {
    FilledButton buttonOf(WidgetTester tester, String label) => tester.widget<FilledButton>(
      find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((widget) => widget is FilledButton)),
    );
    Color? fillOf(WidgetTester tester, String label) =>
        buttonOf(tester, label).style?.backgroundColor?.resolve(const <WidgetState>{});
    OutlinedBorder? shapeOf(WidgetTester tester, String label) =>
        buttonOf(tester, label).style?.shape?.resolve(const <WidgetState>{});

    for (final variant in AppThemeVariant.values) {
      testWidgets('${variant.name}: two buttons of one shape, the focused one filled, no ring', (tester) async {
        await pumpPanel(tester, variant: variant);
        final context = tester.element(find.text(t.common.play));

        final play = shapeOf(tester, t.common.play);
        final close = shapeOf(tester, t.videoControls.closeUpNext);
        expect(play, close, reason: 'a pill beside a box was the mismatch');
        // Both redesign palettes ("Ocker" and "Schwarz") are the one look.
        if (isOcker(context)) {
          expect(play, RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens(context).radiusSm)));
        } else {
          expect(play, const StadiumBorder());
        }

        // Under a remote: the cursor is on Play, and Play alone is lit.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        final lit = fillOf(tester, t.common.play);
        final unlit = fillOf(tester, t.videoControls.closeUpNext);
        expect(lit, isNot(unlit));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(fillOf(tester, t.videoControls.closeUpNext), lit, reason: 'the fill follows the cursor');
        expect(fillOf(tester, t.common.play), unlit);

        // The fill is the focus mark: nothing draws a border round a button.
        final borders = tester
            .widgetList<Container>(
              find.descendant(of: find.byType(PlayerUpNextPanel), matching: find.byType(Container)),
            )
            .map((container) => container.decoration)
            .whereType<BoxDecoration>()
            .where((decoration) => decoration.border != null);
        expect(borders, isEmpty);
      });
    }
  });

  testWidgets('under glass the card is a pane over the picture; elsewhere it is filled', (tester) async {
    await pumpPanel(tester, variant: AppThemeVariant.glas);
    expect(find.ancestor(of: find.text('Breaking Bad'), matching: find.byType(OckerGlass)), findsOneWidget);

    await pumpPanel(tester, variant: AppThemeVariant.standard);
    expect(find.byType(OckerGlass), findsNothing);
  });

  testWidgets('hidden means nothing on screen', (tester) async {
    await pumpPanel(tester, visible: false);

    expect(find.text('Breaking Bad'), findsNothing);
  });
}
