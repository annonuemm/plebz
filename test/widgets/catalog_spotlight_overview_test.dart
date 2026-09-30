import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/cycling_media_backdrop.dart';
import 'package:plezy/widgets/tv_spotlight_scaffold.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

/// Explore rows carry no description — providers only return one with their
/// detail payload — so the spotlight fetches it. This pumps the catalog-aware
/// layer itself, because that is where the wiring lives: testing the widget
/// underneath it once proved a feature "works" while the screen showed nothing.
class _FakeSource implements CatalogSource {
  _FakeSource({this.overview = 'Worum es geht.'});

  final String? overview;
  static const backdropUrl = 'https://plex/art.jpg';
  int detailCalls = 0;

  @override
  CatalogSourceId get id => CatalogSourceId.plex;

  @override
  String get displayName => 'Fake';

  @override
  bool get supportsWatchlist => false;

  @override
  Future<CatalogDetail> fetchDetail(CatalogItem item, {int castLimit = 20, int relatedLimit = 20}) async {
    detailCalls++;
    return CatalogDetail(
      item: CatalogItem(
        source: item.source,
        kind: item.kind,
        title: item.title,
        ids: item.ids,
        overview: overview,
        backdropUrl: backdropUrl,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSources extends CatalogSourcesProvider {
  _TestSources(this._source);

  final CatalogSource _source;

  @override
  List<CatalogSource> get connectedSources => [_source];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const row = CatalogItem(
    source: CatalogSourceId.plex,
    kind: MediaKind.show,
    title: 'Eine Serie',
    // What a Plex Discover row actually carries: its own rating key, and no
    // external id an artwork provider could be asked with.
    ids: CatalogItemIds(plex: '5d9c0874'),
  );

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    LocaleSettings.setLocaleSync(AppLocale.en);
    await SettingsService.getInstance();
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> pump(WidgetTester tester, CatalogSourcesProvider sources, {CatalogItem item = row}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<CatalogSourcesProvider>.value(
        value: sources,
        child: TranslationProvider(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox.expand(
                child: CatalogSpotlightBackground(
                  item: item.toMediaItem(),
                  client: null,
                  hideSpoilers: false,
                  contentTop: 80,
                  contentBottom: 200,
                  contentLeft: 24,
                  targetWidthPx: 1920,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a row without a description gets one from its own provider', (tester) async {
    final source = _FakeSource();
    final sources = _TestSources(source);
    addTearDown(sources.dispose);

    await pump(tester, sources);

    expect(find.text('Worum es geht.'), findsOneWidget);
    expect(source.detailCalls, 1);
  });

  testWidgets('a row that already carries everything is not fetched', (tester) async {
    final source = _FakeSource();
    final sources = _TestSources(source);
    addTearDown(sources.dispose);

    await pump(
      tester,
      sources,
      item: const CatalogItem(
        source: CatalogSourceId.plex,
        kind: MediaKind.show,
        title: 'Eine Serie',
        ids: CatalogItemIds(plex: '5d9c0874'),
        overview: 'Steht schon in der Zeile.',
        backdropUrl: 'https://plex/art.jpg',
      ),
    );

    expect(find.text('Steht schon in der Zeile.'), findsOneWidget);
    expect(source.detailCalls, 0);
  });

  testWidgets('a row with a description but no wide artwork is still fetched', (tester) async {
    final source = _FakeSource();
    final sources = _TestSources(source);
    addTearDown(sources.dispose);

    // Without this the spotlight has nothing but the poster to fill a 16:9
    // screen with, and blows it up.
    await pump(
      tester,
      sources,
      item: const CatalogItem(
        source: CatalogSourceId.plex,
        kind: MediaKind.show,
        title: 'Eine Serie',
        ids: CatalogItemIds(plex: '5d9c0874'),
        overview: 'Steht schon in der Zeile.',
      ),
    );

    expect(source.detailCalls, 1);
    expect(sources.detailItemFor(row)?.backdropUrl, 'https://plex/art.jpg');
  });

  testWidgets('the fetched detail carries the wide artwork the row lacked', (tester) async {
    final source = _FakeSource();
    final sources = _TestSources(source);
    addTearDown(sources.dispose);

    await pump(tester, sources);

    expect(sources.detailItemFor(row)?.backdropUrl, 'https://plex/art.jpg');
  });

  testWidgets('the wide backdrop wins over a banner', (tester) async {
    final source = _FakeSource();
    final sources = _TestSources(source);
    addTearDown(sources.dispose);

    // A Plex banner is much wider than the spotlight's box, so filling the box
    // with it magnifies the same photograph and cuts its sides off.
    await pump(
      tester,
      sources,
      item: const CatalogItem(
        source: CatalogSourceId.plex,
        kind: MediaKind.show,
        title: 'Eine Serie',
        ids: CatalogItemIds(plex: '5d9c0874'),
        overview: 'Steht schon in der Zeile.',
        backdropUrl: 'https://plex/art.jpg',
        bannerUrl: 'https://plex/banner.jpg',
      ),
    );

    final backdrop = tester.widget<CyclingMediaBackdrop>(find.byType(CyclingMediaBackdrop));
    expect(backdrop.imagePaths, contains('https://plex/art.jpg'));
    expect(backdrop.imagePaths, isNot(contains('https://plex/banner.jpg')));
  });

  testWidgets('a banner is still used when there is no backdrop', (tester) async {
    final source = _FakeSource();
    final sources = _TestSources(source);
    addTearDown(sources.dispose);

    await pump(
      tester,
      sources,
      item: const CatalogItem(
        source: CatalogSourceId.plex,
        kind: MediaKind.show,
        title: 'Eine Serie',
        ids: CatalogItemIds(plex: '5d9c0874'),
        overview: 'Steht schon in der Zeile.',
        bannerUrl: 'https://plex/banner.jpg',
      ),
    );

    final backdrop = tester.widget<CyclingMediaBackdrop>(find.byType(CyclingMediaBackdrop));
    expect(backdrop.imagePaths, contains('https://plex/banner.jpg'));
  });

  testWidgets('a provider with no description leaves the spotlight as it was', (tester) async {
    final source = _FakeSource(overview: null);
    final sources = _TestSources(source);
    addTearDown(sources.dispose);

    await pump(tester, sources);

    expect(find.text('Eine Serie'), findsOneWidget, reason: 'the title stays, nothing else appears');
    expect(source.detailCalls, 1);
  });

  testWidgets('the description is fetched once per title, not once per build', (tester) async {
    final source = _FakeSource();
    final sources = _TestSources(source);
    addTearDown(sources.dispose);

    await pump(tester, sources);
    await pump(tester, sources);

    expect(source.detailCalls, 1);
  });
}
