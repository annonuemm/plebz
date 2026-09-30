import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/widgets/media_rating_badge.dart';

import '../test_helpers/prefs.dart';

/// The four badges a Plex movie detail page carries: TMDB 79%, IMDb 7.4,
/// Rotten Tomatoes 95% and its audience panel 96%, all stored on the shared
/// 0-10 scale. Their mean is 8.6.
const _fourScoreMovie = MediaItem.plex(
  id: 'movie_1',
  kind: MediaKind.movie,
  title: 'Four Score Movie',
  rating: 7.9,
  ratings: [
    MediaRatingSource(source: 'tmdb', value: 7.9),
    MediaRatingSource(source: 'imdb', value: 7.4),
    MediaRatingSource(source: 'rottenTomatoesCritic', value: 9.5),
    MediaRatingSource(source: 'rottenTomatoesAudience', value: 9.6),
  ],
);

Future<void> _pumpBadges(WidgetTester tester, MediaItem item) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        home: Scaffold(
          body: Center(child: MediaRatingBadgeGroup.chip(item: item)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  testWidgets('every source keeps its own badge by default', (tester) async {
    await _pumpBadges(tester, _fourScoreMovie);

    expect(SettingsService.instance.read(SettingsService.averageRatings), isFalse);
    expect(find.text('79%'), findsOneWidget);
    expect(find.text('7.4'), findsOneWidget);
    expect(find.text('95%'), findsOneWidget);
    expect(find.text('96%'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNWidgets(4));
  });

  testWidgets('the setting collapses the four badges into one mean score', (tester) async {
    await SettingsService.instance.write(SettingsService.averageRatings, true);
    await _pumpBadges(tester, _fourScoreMovie);

    expect(find.text('8.6'), findsOneWidget);
    expect(find.text('79%'), findsNothing);
    expect(find.text('7.4'), findsNothing);
    expect(find.text('95%'), findsNothing);
    expect(find.text('96%'), findsNothing);
    // The mean belongs to no brand, so no logo is drawn for it.
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('the pill follows the switch without being rebuilt by its parent', (tester) async {
    await _pumpBadges(tester, _fourScoreMovie);
    expect(find.text('7.4'), findsOneWidget);

    await SettingsService.instance.write(SettingsService.averageRatings, true);
    await tester.pumpAndSettle();

    expect(find.text('8.6'), findsOneWidget);
    expect(find.text('7.4'), findsNothing);
  });

  testWidgets('a lone score is shown as itself, not as an average of one', (tester) async {
    await SettingsService.instance.write(SettingsService.averageRatings, true);
    await _pumpBadges(
      tester,
      const MediaItem.jellyfin(
        id: 'movie_2',
        kind: MediaKind.movie,
        title: 'Community Only',
        rating: 8.3,
        ratings: [MediaRatingSource(source: 'imdb', value: 8.3)],
      ),
    );

    expect(find.text('8.3'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget, reason: 'the IMDb logo survives when nothing is combined');
  });

  testWidgets('an item with no scores renders nothing either way', (tester) async {
    await SettingsService.instance.write(SettingsService.averageRatings, true);
    await _pumpBadges(tester, const MediaItem.plex(id: 'movie_3', kind: MediaKind.movie, title: 'Unrated'));

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byType(Text), findsNothing);
  });
}
