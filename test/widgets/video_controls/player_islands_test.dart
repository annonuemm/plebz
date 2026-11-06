import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/video_volume_controller.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/watch_together/providers/watch_together_provider.dart';
import 'package:plezy/widgets/app_bar_back_button.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:plezy/widgets/system_clock.dart';
import 'package:plezy/widgets/video_controls/desktop_video_controls.dart';
import 'package:plezy/widgets/video_controls/widgets/content_strip.dart';
import 'package:plezy/focus/card_focus_scope.dart';
import 'package:plezy/widgets/video_controls/models/track_controls_state.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/media_items.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/watch_together_fakes.dart';

/// Plebz: the television's player under the redesign — the title over the
/// timeline, the buttons bare under it, nothing shown that has nothing to do.
void main() {
  setUp(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    debugOckerLayoutOnThisHost = true;
  });
  tearDown(() {
    debugOckerLayoutOnThisHost = null;
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  Future<void> pumpControls(
    WidgetTester tester, {
    AppThemeVariant variant = AppThemeVariant.glasV2,
    MediaItem? item,
    List<MediaChapter> chapters = const [],
    bool withNeighbours = false,
    bool live = false,
  }) async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    final settings = await SettingsService.getInstance();
    final player = FakeSyncPlayer();
    addTearDown(player.dispose);
    final volume = VideoVolumeController(player: player, settings: settings, initialVolume: 100);
    addTearDown(volume.dispose);
    final watchTogether = WatchTogetherProvider();
    addTearDown(watchTogether.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<WatchTogetherProvider>.value(
        value: watchTogether,
        child: MaterialApp(
          theme: monoTheme(MonoPalette.dark, variant: variant),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: DesktopVideoControls(
              useDpadNavigation: true,
              player: player,
              volumeController: volume,
              metadata: item ?? testMediaItem(id: 'film', title: 'The Film', year: 2013),
              onPlayPause: () {},
              onNext: withNeighbours ? () {} : null,
              onPrevious: withNeighbours ? () {} : null,
              chapters: chapters,
              chaptersLoaded: true,
              seekTimeSmall: 10,
              onSeekToPreviousChapter: () {},
              onSeekToNextChapter: () {},
              onSeek: (_) {},
              onSeekEnd: (_) {},
              getReplayIcon: (_) => Icons.replay_10,
              getForwardIcon: (_) => Icons.forward_10,
              trackControlsState: TrackControlsState(canControl: true, isLive: live),
              liveChannelName: live ? 'Das Erste' : null,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  Finder button(String label) => find.bySemanticsLabel(label);
  String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

  for (final variant in [AppThemeVariant.glasV2, AppThemeVariant.flach]) {
    testWidgets('${variant.name}: the title over the timeline, the buttons bare under it', (tester) async {
      await pumpControls(tester, variant: variant);

      final islands = find.byKey(const ValueKey('player_islands'));
      expect(islands, findsOneWidget);
      // No pane round the buttons, neither glass nor a flat fill.
      expect(find.descendant(of: islands, matching: find.byType(OckerGlass)), findsNothing);
      // Playback on the left, the tools on the right.
      final glyphs = find.descendant(of: islands, matching: find.byType(IconButton));
      expect(
        tester.getCenter(find.descendant(of: islands, matching: button(t.videoControls.playButton))).dx,
        lessThan(1920 / 4),
      );
      // The outermost glyphs stand flush with the title's margin.
      final margin = OckerLayout.safeMargin * 0.5;
      expect(tester.getTopLeft(glyphs.first).dx + 8, moreOrLessEquals(margin, epsilon: 0.5));
      expect(tester.getTopRight(glyphs.last).dx - 8, moreOrLessEquals(960 - margin, epsilon: 0.5));

      final title = find.byKey(const ValueKey('player_island_title'));
      expect(find.descendant(of: title, matching: find.text('The Film')), findsOneWidget);
      expect(find.descendant(of: title, matching: find.text('2013')), findsOneWidget);
      // The title stands at the page's margin, over the timeline.
      expect(tester.getTopLeft(title).dx, moreOrLessEquals(margin, epsilon: 0.5));
      expect(tester.getBottomLeft(title).dy, lessThan(tester.getTopLeft(islands).dy));

      // Back is the remote's; the clock stays in its corner.
      expect(find.byType(AppBarBackButton), findsNothing);
      expect(find.byType(SystemClock), findsOneWidget);
    });
  }

  testWidgets('leaves out the chapter jumps and the neighbours a film does not have', (tester) async {
    await pumpControls(tester);

    expect(button(t.videoControls.seekBackwardButton(seconds: 10)), findsOneWidget);
    expect(button(t.videoControls.playButton), findsOneWidget);
    expect(button(t.videoControls.seekForwardButton(seconds: 10)), findsOneWidget);
    expect(button(t.videoControls.previousButton), findsNothing);
    expect(button(t.videoControls.nextButton), findsNothing);
    expect(button(t.videoControls.previousChapterButton), findsNothing);
    expect(button(t.videoControls.nextChapterButton), findsNothing);
  });

  testWidgets('play sits optically centred in its disc, pause by its box', (tester) async {
    await pumpControls(tester);
    final play = find.descendant(of: button(t.videoControls.playButton), matching: find.byType(IconButton));
    // The glyph itself, inside the shift — the shift moves only what it paints.
    final glyph = find.descendant(
      of: find.descendant(of: play, matching: find.byType(Transform)),
      matching: find.byType(AppIcon),
    );
    expect(glyph, findsOneWidget);
    expect(tester.getCenter(glyph).dx - tester.getCenter(play).dx, moreOrLessEquals(32 * 0.06, epsilon: 0.01));
  });

  testWidgets('keeps every jump that has somewhere to go', (tester) async {
    await pumpControls(
      tester,
      withNeighbours: true,
      chapters: [
        MediaChapter(id: 1, startTimeOffset: 0, title: 'Opening'),
        MediaChapter(id: 2, startTimeOffset: 600000, title: 'Middle'),
      ],
    );

    for (final label in [
      t.videoControls.previousButton,
      t.videoControls.previousChapterButton,
      t.videoControls.seekBackwardButton(seconds: 10),
      t.videoControls.playButton,
      t.videoControls.seekForwardButton(seconds: 10),
      t.videoControls.nextChapterButton,
      t.videoControls.nextButton,
    ]) {
      expect(button(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the remote steps over a left-out button and on into the tools', (tester) async {
    await pumpControls(tester);
    final play = find.descendant(
      of: find.byKey(const ValueKey('player_islands')),
      matching: find.byWidgetPredicate((w) => w is Focus && w.focusNode?.debugLabel == 'PlayPause'),
    );
    tester.widget<Focus>(play.first).focusNode!.requestFocus();
    await tester.pump();
    expect(focused(), 'PlayPause');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(focused(), 'SkipBack');
    // Nothing further left: the previous title and chapter are not there.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(focused(), 'SkipBack');

    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(focused(), 'SkipForward');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focused(), 'TrackControl0', reason: 'from the last playback button into the tools capsule');
  });

  testWidgets("an episode names its show, over the season and episode", (tester) async {
    await pumpControls(
      tester,
      item: testMediaItem(
        id: 'ep',
        kind: MediaKind.episode,
        title: 'Pilot',
        grandparentTitle: 'The Show',
        parentIndex: 1,
        index: 3,
      ),
    );

    final title = find.byKey(const ValueKey('player_island_title'));
    expect(find.descendant(of: title, matching: find.text('The Show')), findsOneWidget);
    expect(find.descendant(of: title, matching: find.textContaining('S1')), findsOneWidget);
    expect(find.descendant(of: title, matching: find.textContaining('Pilot')), findsOneWidget);
  });

  for (final variant in [AppThemeVariant.glasV2, AppThemeVariant.flach]) {
    testWidgets('${variant.name}: Down opens the chapters as a row of the start page', (tester) async {
      await pumpControls(
        tester,
        variant: variant,
        chapters: [
          MediaChapter(id: 1, startTimeOffset: 0, title: 'Opening'),
          MediaChapter(id: 2, startTimeOffset: 600000, title: 'Middle'),
        ],
      );
      final play = find.byWidgetPredicate((w) => w is Focus && w.focusNode?.debugLabel == 'PlayPause');
      tester.widget<Focus>(play.first).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 300));

      final strip = find.byType(ContentStrip);
      expect(strip, findsOneWidget);
      expect(tester.widget<ContentStrip>(strip).rowLook, isTrue);
      // No pane under it, neither glass nor a flat fill.
      expect(find.ancestor(of: strip, matching: find.byType(OckerGlass)), findsNothing);
      expect(find.descendant(of: strip, matching: find.byType(OckerGlass)), findsNothing);
      // The heading at the page's margin, the first picture under it.
      final heading = find.byKey(const ValueKey('strip_heading_chapters'));
      final margin = OckerLayout.safeMargin * 0.5;
      expect(tester.getTopLeft(heading).dx, moreOrLessEquals(margin, epsilon: 0.5));
      expect(find.text('Opening'), findsOneWidget);
      // The chapter playing carries the mark, and focus starts on it as a
      // ring round its picture.
      expect(find.byKey(const ValueKey('strip_playing_chip')), findsOneWidget);
      expect(find.text(t.videoControls.playingNow), findsOneWidget);
      expect(focused(), 'ChapterFocus0');
      expect(find.descendant(of: strip, matching: find.byType(CardFocusBorder)), findsNWidgets(2));

      // Up returns to the buttons.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ContentStrip), findsNothing);
      expect(focused(), 'PlayPause');
    });
  }

  testWidgets('a live channel is named without a LIVE badge beside it', (tester) async {
    await pumpControls(tester, live: true);

    final title = find.byKey(const ValueKey('player_island_title'));
    expect(find.descendant(of: title, matching: find.text('Das Erste')), findsOneWidget);
    expect(find.text(t.liveTv.live), findsNothing);
  });

  testWidgets('a Mac keeps the bar', (tester) async {
    debugOckerLayoutOnThisHost = false;
    TvDetectionService.debugSetAppleTVOverride(null);
    await pumpControls(tester);

    expect(find.byKey(const ValueKey('player_islands')), findsNothing);
    expect(find.byType(AppBarBackButton), findsOneWidget);
  });
}
