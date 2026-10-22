import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/video_player/widgets/player_up_next_panel.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/media_items.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

/// The end card (Plebz, the user's design 2026-10-14): the whole screen at an
/// episode's end, the playing picture moved into a box on the left and the
/// next episode beside it.
void main() {
  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.de);
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  final current = testMediaItem(
    id: 'ep-4',
    backend: MediaBackend.plex,
    kind: MediaKind.episode,
    title: 'Der Hafen',
    grandparentTitle: 'Sarah Kohr',
  );
  final next = testMediaItem(
    id: 'ep-5',
    backend: MediaBackend.plex,
    kind: MediaKind.episode,
    title: 'Die Brücke',
    grandparentTitle: 'Sarah Kohr',
    summary: 'Ein Informant meldet sich bei Sarah Kohr.',
    parentIndex: 2,
    index: 5,
    year: 2025,
    durationMs: 88 * 60 * 1000,
  );

  Future<({List<Rect?> placed, ValueNotifier<bool> open, List<String> taps})> pumpCard(
    WidgetTester tester, {
    bool movesPicture = true,
  }) async {
    final placed = <Rect?>[];
    final taps = <String>[];
    final open = ValueNotifier(false);
    final multiServer = testMultiServerProvider(MultiServerManager());
    final play = FocusNode();
    final credits = FocusNode();
    final exit = FocusNode();
    addTearDown(() {
      exit.dispose();
      multiServer.dispose();
      play.dispose();
      credits.dispose();
      open.dispose();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: multiServer,
          child: MaterialApp(
            theme: monoTheme(MonoPalette.dark, variant: AppThemeVariant.glas),
            builder: (context, child) => InputModeTracker(child: child!),
            home: Scaffold(
              backgroundColor: Colors.transparent,
              body: ValueListenableBuilder<bool>(
                valueListenable: open,
                builder: (context, isOpen, _) => PlayerEndCard(
                  open: isOpen,
                  current: current,
                  next: next,
                  movesPicture: movesPicture,
                  placePicture: placed.add,
                  playLabel: ValueNotifier('Startet in 8 s'),
                  remaining: ValueNotifier(const Duration(minutes: 1, seconds: 12)),
                  playFocusNode: play,
                  creditsFocusNode: credits,
                  onPlay: () => taps.add('play'),
                  onWatchCredits: () => taps.add('credits'),
                  exitFocusNode: exit,
                  onExit: () => taps.add('exit'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return (placed: placed, open: open, taps: taps);
  }

  testWidgets('shut, it is nothing at all', (tester) async {
    final card = await pumpCard(tester);
    expect(find.text('Die Brücke'), findsNothing);
    expect(card.placed, isEmpty, reason: 'the picture is left where it is');
  });

  testWidgets('opening moves the picture into its box and sets the next episode beside it', (tester) async {
    final card = await pumpCard(tester);
    card.open.value = true;
    await tester.pumpAndSettle();

    final box = PlayerEndCard.pictureBox(const Size(1280, 720));
    expect(card.placed.last, box, reason: 'the picture ends up in the box, frame by frame');
    expect(card.placed.length, greaterThan(2), reason: 'it moves there, it does not jump');
    for (final text in ['Sarah Kohr', 'Die Brücke', 'Ein Informant meldet sich bei Sarah Kohr.', 'Startet in 8 s']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.textContaining('Staffel 2, Folge 5'), findsOneWidget);
    expect(find.text('Der Hafen'), findsOneWidget, reason: 'the playing episode is named under its box');
    expect(find.text('noch 1:12'), findsOneWidget);

    await tester.tap(find.text('Abspann'));
    await tester.tap(find.text('Startet in 8 s'));
    await tester.tap(find.text('Beenden'));
    expect(card.taps, ['credits', 'play', 'exit']);
  });

  testWidgets('closing grows the picture back to the whole screen', (tester) async {
    final card = await pumpCard(tester);
    card.open.value = true;
    await tester.pumpAndSettle();
    card.open.value = false;
    await tester.pumpAndSettle();

    expect(card.placed.last, isNull, reason: 'back on the whole screen');
    expect(find.text('Die Brücke'), findsNothing);
  });

  testWidgets('where the picture cannot move, the box shows a still and nothing is placed', (tester) async {
    final card = await pumpCard(tester, movesPicture: false);
    card.open.value = true;
    await tester.pumpAndSettle();
    expect(card.placed, isEmpty);
    expect(find.text('Die Brücke'), findsOneWidget);
  });

  test('until chosen, the style follows the switch it grew out of', () async {
    final settings = SettingsService.instance;
    expect(settings.read(PlebzPrefs.endOfEpisodeStyle), EndOfEpisodeStyle.upNextPanel);
    await settings.write(PlebzPrefs.showUpNextPanel, false);
    expect(settings.read(PlebzPrefs.endOfEpisodeStyle), EndOfEpisodeStyle.plezyPrompt);
    await settings.write(PlebzPrefs.endOfEpisodeStyle, EndOfEpisodeStyle.endCard);
    expect(settings.read(PlebzPrefs.endOfEpisodeStyle), EndOfEpisodeStyle.endCard);
    expect(settings.read(PlebzPrefs.endCardBackFrom), 95);
  });
}
