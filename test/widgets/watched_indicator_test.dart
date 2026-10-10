import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';
import 'package:plezy/widgets/media_progress_bar.dart';
import 'package:plezy/widgets/unwatched_count_badge.dart';
import 'package:plezy/widgets/watched_indicator.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  Future<void> pump(WidgetTester tester, WatchedIndicator indicator) => tester.pumpWidget(
    MaterialApp(
      theme: monoTheme(dark: true),
      home: SizedBox(width: 200, height: 300, child: indicator),
    ),
  );

  final watchedMovie = testMediaItem(id: 'movie', kind: MediaKind.movie, viewCount: 1);

  testWidgets('shows the watched checkmark by default', (tester) async {
    await pump(tester, WatchedIndicator(item: watchedMovie));

    expect(find.byIcon(Symbols.check_rounded), findsOneWidget);
  });

  testWidgets('hides only the checkmark when watched indicators are off (#1998)', (tester) async {
    await SettingsService.instance.write(SettingsService.showWatchedIndicators, false);
    final partiallyWatchedShow = testMediaItem(id: 'show', kind: MediaKind.show, leafCount: 10, viewedLeafCount: 4);
    final inProgressMovie = testMediaItem(
      id: 'movie-2',
      kind: MediaKind.movie,
      durationMs: 100000,
      viewOffsetMs: 50000,
    );

    await pump(tester, WatchedIndicator(item: watchedMovie));
    expect(find.byIcon(Symbols.check_rounded), findsNothing);

    await pump(tester, WatchedIndicator(item: partiallyWatchedShow));
    expect(find.byType(UnwatchedCountBadge), findsOneWidget, reason: 'unwatched counts are a separate pref');

    await pump(tester, WatchedIndicator(item: inProgressMovie));
    expect(find.byType(MediaProgressBar), findsOneWidget, reason: 'progress bars are not indicators');
  });

  group('the progress bar', () {
    final inProgressMovie = testMediaItem(
      id: 'movie-3',
      kind: MediaKind.movie,
      durationMs: 100000,
      viewOffsetMs: 40000,
    );

    Future<(Rect, Color)> barOn(WidgetTester tester, ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 300,
              child: Stack(children: [WatchedIndicator(item: inProgressMovie)]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bar = find.byType(LinearProgressIndicator);
      final colour = tester.widget<LinearProgressIndicator>(bar).valueColor!.value!;
      return (tester.getRect(bar), colour);
    }

    testWidgets('floats inside the picture in both redesigns: white under Glas, the accent under Flach', (
      tester,
    ) async {
      final glas = monoTheme(dark: true, variant: AppThemeVariant.glas);
      final (glasBar, glasFill) = await barOn(tester, glas);
      expect(glasBar.left, closeTo(14, 0.5), reason: 'room from the side');
      expect(200 - glasBar.right, closeTo(14, 0.5));
      expect(300 - glasBar.bottom, closeTo(7.7, 0.5), reason: 'less room from the foot: it sits low');
      expect(glasBar.height, 5);
      expect(glasFill, glas.extension<MonoTokens>()!.ink(1));

      final flach = monoTheme(dark: true, variant: AppThemeVariant.flach);
      final (flachBar, flachFill) = await barOn(tester, flach);
      expect(flachBar, glasBar, reason: 'the same place in both');
      expect(flachFill, flach.extension<MonoTokens>()!.accent);
    });

    testWidgets('the standard design keeps it along the bottom edge', (tester) async {
      final (bar, _) = await barOn(tester, monoTheme(dark: true));
      expect(bar.left, 0);
      expect(bar.right, 200);
      expect(bar.bottom, 300);
    });
  });
}
