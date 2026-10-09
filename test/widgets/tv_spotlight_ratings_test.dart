import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/content_utils.dart';
import 'package:plezy/utils/formatters.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/optimized_media_image.dart';
import 'package:plezy/widgets/tv_spotlight_background.dart';

import '../test_helpers/prefs.dart';

/// The TV dashboard spotlight (Discover, Explore, and the library recommended
/// tab all render through [TvSpotlightBackground]) shows every score the hub
/// listing already returned. Listings carry the scalar rating pair, so this is
/// normally one or two entries — never a reason to re-fetch an item.
Future<void> _pumpSpotlight(WidgetTester tester, MediaItem item, {AppThemeVariant? variant}) async {
  await SettingsService.getInstance();
  // Per-source scores: averaging is on by default in this fork.
  await SettingsService.instance.write(SettingsService.averageRatings, false);
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: variant == null ? null : monoTheme(dark: true, variant: variant),
        home: Scaffold(
          // TvSpotlightScaffold fills the screen with the background; a loose
          // Scaffold body would leave its bottom-anchored info block unbounded.
          body: SizedBox.expand(
            child: TvSpotlightBackground(
              item: item,
              client: null,
              allowNetwork: false,
              compact: true,
              contentTop: 80,
              contentBottom: 200,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  testWidgets('under glass the spotlight\'s facts lie on capsules of glass, without bullets', (tester) async {
    await _pumpSpotlight(
      tester,
      const MediaItem.plex(
        id: 'movie_2',
        kind: MediaKind.movie,
        title: 'Glass Movie',
        year: 1992,
        durationMs: 2700000,
        summary: 'A short synopsis.',
      ),
      variant: AppThemeVariant.glas,
    );

    expect(find.ancestor(of: find.text('1992'), matching: find.byType(OckerGlassPlate)), findsOneWidget);
    expect(find.textContaining('•'), findsNothing);
    // On "Flach"'s step to the synopsis (ockerFlatSizes): 22 at this scale.
    final chip = tester.getRect(find.ancestor(of: find.text('1992'), matching: find.byType(OckerGlassPlate)));
    final synopsis = tester.getRect(find.text('A short synopsis.'));
    expect(synopsis.top - chip.bottom, closeTo(22, 0.5));
  });

  testWidgets('the spotlight\'s facts follow the detail page\'s order', (tester) async {
    await _pumpSpotlight(
      tester,
      const MediaItem.plex(
        id: 'movie_4',
        kind: MediaKind.movie,
        title: 'Order Movie',
        year: 1992,
        contentRating: 'PG-13',
        durationMs: 2700000,
        editionTitle: 'Extended',
      ),
      variant: AppThemeVariant.glas,
    );

    final order = ['1992', t.discover.movie, formatContentRating('PG-13'), formatDurationTextual(2700000), 'Extended'];
    final lefts = [for (final text in order) tester.getRect(find.text(text)).left];
    expect(lefts, [...lefts]..sort(), reason: 'year, kind, age, length, edition');
  });

  testWidgets('the spotlight sets the title as type where logos are switched off here', (tester) async {
    const item = MediaItem.plex(
      id: 'movie_3',
      kind: MediaKind.movie,
      title: 'Logo Movie',
      clearLogoPath: '/library/metadata/3/clearLogo',
    );
    await _pumpSpotlight(tester, item);
    expect(tester.widget<ClearLogoImage>(find.byType(ClearLogoImage)).logoPath, isNotNull, reason: 'on by default');

    await SettingsService.instance.write(SettingsService.showHomeTitleLogos, false);
    await tester.pump();
    final off = tester.widget<ClearLogoImage>(find.byType(ClearLogoImage));
    expect(off.logoPath, isNull, reason: 'no logo shown');
    expect(off.item, isNull, reason: 'and none looked for');
    expect(find.text('Logo Movie'), findsWidgets, reason: 'the title as type in its place');
  });

  testWidgets('dashboard spotlight badges every rating the listing carried', (tester) async {
    await _pumpSpotlight(
      tester,
      const MediaItem.plex(
        id: 'movie_1',
        kind: MediaKind.movie,
        title: 'Spotlight Movie',
        rating: 9.2,
        ratings: [
          MediaRatingSource(source: 'rottenTomatoesCritic', value: 9.2),
          MediaRatingSource(source: 'rottenTomatoesAudience', value: 8.5),
        ],
      ),
    );

    expect(find.text('92%'), findsOneWidget);
    expect(find.text('85%'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNWidgets(2));
  });

  testWidgets('dashboard spotlight still shows one badge for a single-score listing', (tester) async {
    await _pumpSpotlight(
      tester,
      const MediaItem.jellyfin(
        id: 'movie_2',
        kind: MediaKind.movie,
        title: 'Community Only',
        rating: 8.3,
        ratings: [MediaRatingSource(source: 'audience', value: 8.3)],
      ),
    );

    // No brand logo exists for an unattributed community score, so it keeps
    // the generic icon and the neutral 0-10 rendering.
    expect(find.text('8.3'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('dashboard spotlight omits the rating slot when the item has no score', (tester) async {
    await _pumpSpotlight(
      tester,
      const MediaItem.plex(id: 'movie_3', kind: MediaKind.movie, title: 'Unrated', year: 2024),
    );

    expect(find.text('2024'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('dashboard spotlight announces each rating with its source name', (tester) async {
    final semantics = tester.ensureSemantics();

    await _pumpSpotlight(
      tester,
      const MediaItem.plex(
        id: 'movie_4',
        kind: MediaKind.movie,
        title: 'Announced Movie',
        ratings: [
          MediaRatingSource(source: 'rottenTomatoesCritic', value: 9.2),
          MediaRatingSource(source: 'imdb', value: 7.4),
        ],
      ),
    );

    // Without the group's own label a reader would hear "92%, 7.4" with no
    // way to tell which score belongs to which source.
    expect(
      find.bySemanticsLabel('${t.common.ratingSource.rottenTomatoesCritic} 92%, ${t.common.ratingSource.imdb} 7.4'),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
