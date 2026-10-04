import 'dart:async';

import 'package:flutter/material.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/focus/focusable_action_bar.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/watchlist_filter.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/models/catalog/catalog_cast_member.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/models/catalog/catalog_metadata.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/screens/hub_detail_screen.dart';
import 'package:plezy/redesign/ocker_detail_panel.dart';
import 'package:plezy/redesign/ocker_poster_tile.dart';
import 'package:plezy/widgets/focusable_tab_chip.dart';
import 'package:plezy/screens/watchlist_screen.dart';
import 'package:plezy/services/catalog/local_watchlist.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';

/// A provider with a watchlist of [total] titles, paged the way the real
/// sources page.
class _FakeWatchlistSource implements CatalogSource {
  _FakeWatchlistSource(
    this.id,
    this.displayName, {
    this.total = 3,
    this.supportsWatchlist = true,
    this.shape,
    this.detail,
    this.gate,
  });

  /// Held open, the first page does not arrive until it completes — a list
  /// still loading.
  final Future<void>? gate;

  /// What a detail fetch answers. Null leaves it unanswered, as most of these
  /// tests have no use for one.
  final CatalogDetail Function(CatalogItem item)? detail;

  /// The cast limit every detail fetch asked for.
  final detailCastLimits = <int>[];

  @override
  Future<CatalogDetail> fetchDetail(CatalogItem item, {int castLimit = 20, int relatedLimit = 20}) async {
    detailCastLimits.add(castLimit);
    final answer = detail;
    if (answer == null) throw UnimplementedError('no detail in this test');
    return answer(item);
  }

  /// What each entry is, cycled over the list. Null makes every entry an
  /// unwatched film, which is all most of these tests care about.
  final List<({MediaKind kind, bool? watched})>? shape;

  @override
  final CatalogSourceId id;

  @override
  final String displayName;

  final int total;

  @override
  final bool supportsWatchlist;

  final _watchlistChanges = WatchlistChangeNotifier();
  final rowFetches = <(CatalogRowId row, int page, int limit)>[];

  @override
  Listenable get watchlistChanges => _watchlistChanges;

  @override
  Future<CatalogPage> fetchRow(CatalogRowId row, {int page = 1, int limit = 25}) async {
    rowFetches.add((row, page, limit));
    await gate;
    final start = (page - 1) * limit;
    final end = start + limit > total ? total : start + limit;
    return CatalogPage(
      items: [
        for (var i = start; i < end; i++)
          CatalogItem(
            source: id,
            kind: shape == null ? MediaKind.movie : shape![i % shape!.length].kind,
            isWatched: shape == null ? null : shape![i % shape!.length].watched,
            title: '$displayName Title $i',
            ids: CatalogItemIds(tmdb: i + id.index * 1000),
          ),
      ],
      hasMore: end < total,
      totalResults: total,
    );
  }

  @override
  Future<List<CatalogItem>> search(String query, {int limit = 30}) async => const [];

  @override
  void dispose() => _watchlistChanges.dispose();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A media server whose libraries can answer a favorites query.
class _FakeFavoritesClient implements MediaServerClient {
  _FakeFavoritesClient(this.capabilities);

  @override
  final ServerCapabilities capabilities;

  @override
  ServerId get serverId => ServerId('server-1');

  @override
  MediaBackend get backend => capabilities.userFavorites ? MediaBackend.jellyfin : MediaBackend.plex;

  @override
  void close() {}

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    Object? abort,
  }) async => LibraryPage<MediaItem>(
    items: [testMediaItem(id: 'fav-0', kind: MediaKind.movie, title: 'Favorite 0', serverId: 'server-1')],
    totalCount: 1,
  );

  /// A title the app keeps on the watchlist itself, as the server has it.
  @override
  Future<MediaItem?> fetchItem(String id) async => id == 'kept-1'
      ? testMediaItem(id: 'kept-1', kind: MediaKind.show, title: 'Kept Show', serverId: 'server-1')
      : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaLibrary _library(String id) =>
    MediaLibrary(id: id, backend: MediaBackend.jellyfin, title: 'Library', serverId: 'server-1');

class _FakeLibrariesProvider extends LibrariesProvider {
  _FakeLibrariesProvider(this._libraries);

  final List<MediaLibrary> _libraries;

  @override
  List<MediaLibrary> get libraries => _libraries;
}

class _FakeCatalogSourcesProvider extends CatalogSourcesProvider {
  _FakeCatalogSourcesProvider(this.sources);

  final List<CatalogSource> sources;

  /// The Explore tab's own switcher. The watchlist must not follow it.
  CatalogSourceId? activeId;

  @override
  List<CatalogSource> get connectedSources => sources;

  @override
  CatalogSource? get activeSource =>
      sources.where((source) => source.id == activeId).firstOrNull ?? (sources.isEmpty ? null : sources.first);

  @override
  Future<void> setActiveSource(CatalogSourceId? id, {void Function()? checkCurrent}) async {
    checkCurrent?.call();
    activeId = id;
    notifyListeners();
  }
}

Future<_FakeCatalogSourcesProvider> _pumpWatchlist(
  WidgetTester tester,
  List<CatalogSource> sources, {
  List<MediaLibrary> libraries = const [],
  ServerCapabilities? capabilities,
  AppThemeVariant variant = AppThemeVariant.standard,
  VoidCallback? onSidebar,
  // The glass watchlist of the redesign is the television's page; a phone
  // wears the look alone.
  bool television = true,
}) async {
  if (variant == AppThemeVariant.glas && television) {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
  }
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final provider = _FakeCatalogSourcesProvider(sources);
  addTearDown(provider.dispose);
  for (final source in sources) {
    addTearDown(source.dispose);
  }

  final librariesProvider = _FakeLibrariesProvider(libraries);
  addTearDown(librariesProvider.dispose);
  final servers = capabilities == null ? null : testMultiServer(clients: [_FakeFavoritesClient(capabilities)]).provider;

  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<CatalogSourcesProvider>.value(value: provider),
          ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
          if (servers != null) ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true, variant: variant),
          home: MainScreenFocusScope(
            focusSidebar: onSidebar ?? () {},
            sideNavigationWidth: 0,
            child: const WatchlistScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  setUp(() async {
    resetSharedPreferencesForTest();
    LocalWatchlist.debugReset();
    // Read outside the fake clock: the store answers through real async IO.
    await LocalWatchlist.forProfile('').ensureLoaded();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('renders the watchlist as an embedded hub with no back affordance', (tester) async {
    await _pumpWatchlist(tester, [_FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl')]);

    final hub = tester.widget<HubDetailScreen>(find.byType(HubDetailScreen));
    expect(hub.isEmbedded, isTrue, reason: 'the tab owns no route to pop back to');
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Simkl Title 0'), findsOneWidget);
  });

  testWidgets('a single provider needs no switcher', (tester) async {
    await _pumpWatchlist(tester, [_FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl')]);

    expect(find.text(t.explore.rows.watchlist), findsOneWidget);
    expect(find.text('Simkl'), findsNothing, reason: 'nothing to choose between');
  });

  testWidgets('several providers each get a chip beside the title', (tester) async {
    await _pumpWatchlist(tester, [
      _FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl'),
      _FakeWatchlistSource(CatalogSourceId.plex, 'Plex'),
    ]);

    expect(find.text(t.explore.rows.watchlist), findsOneWidget);
    expect(find.text('Simkl'), findsOneWidget);
    expect(find.text('Plex'), findsOneWidget);
  });

  testWidgets('on a phone under glass the watchlist keeps its own page: tabs for the lists, no panel', (tester) async {
    // The panel beside the posters is a television's arrangement; a phone
    // wears the look alone.
    await _pumpWatchlist(
      tester,
      [_FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl'), _FakeWatchlistSource(CatalogSourceId.plex, 'Plex')],
      variant: AppThemeVariant.glas,
      television: false,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(OckerDetailPanel), findsNothing);
    expect(find.byType(TabChipStrip), findsOneWidget, reason: 'the choice of lists stays on the page');
  });

  testWidgets('under the redesign the lists are rows for the rail and the filters stand over the posters', (
    tester,
  ) async {
    // The rail and the panel beside the posters are the television's layout.
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    var rail = 0;
    await _pumpWatchlist(
      tester,
      [_FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl'), _FakeWatchlistSource(CatalogSourceId.plex, 'Plex')],
      variant: AppThemeVariant.glas,
      onSidebar: () => rail++,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(TabChipStrip), findsNothing, reason: 'the choice of lists is in the rail');

    final state = tester.state<WatchlistScreenState>(find.byType(WatchlistScreen));
    final menu = state.ockerRailMenu!;
    expect(menu.items.map((item) => item.label), ['Simkl', 'Plex']);
    expect(menu.items.first.selected, isTrue);

    final bar = tester.getRect(find.byType(FocusableActionBar));
    final panel = tester.getRect(find.byType(OckerDetailPanel));
    final poster = tester.getRect(find.byType(OckerPosterTile).first);
    expect(panel.left, greaterThan(poster.right), reason: 'the describing column on the right');
    expect(bar.bottom, lessThanOrEqualTo(poster.top), reason: 'the filters over the posters');
    expect(bar.left, lessThan(poster.center.dx), reason: 'at their top left');

    // A keyboard session, so the tiles take and move focus as on a TV.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final first = tester.widget<OckerPosterTile>(find.byType(OckerPosterTile).first);
    first.focusNode.requestFocus();
    await tester.pumpAndSettle();

    bool onFilters() => find
        .ancestor(
          of: find.byWidgetPredicate((w) => w is Focus && w.focusNode == FocusManager.instance.primaryFocus),
          matching: find.byType(FocusableActionBar),
        )
        .evaluate()
        .isNotEmpty;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(onFilters(), isTrue, reason: 'UP out of the first row');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(rail, 1, reason: 'LEFT of the first filter is the rail');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    first.focusNode.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(rail, 2, reason: 'LEFT out of the first column is the rail');

    menu.items.last.onSelect();
    await tester.pumpAndSettle();
    expect(state.ockerRailMenu!.items.firstWhere((item) => item.selected).label, 'Plex');
  });

  testWidgets('under glass the type is written out — all, movies, shows — one press each', (tester) async {
    await _pumpWatchlist(tester, [
      _FakeWatchlistSource(
        CatalogSourceId.plex,
        'Plex',
        total: 4,
        shape: const [(kind: MediaKind.movie, watched: null), (kind: MediaKind.show, watched: null)],
      ),
    ], variant: AppThemeVariant.glas);

    expect(find.text(t.watchlist.typeAll), findsOneWidget);
    expect(find.text(t.watchlist.typeMovies), findsOneWidget);
    expect(find.text(t.watchlist.typeShows), findsOneWidget);
    expect(find.byType(OckerPosterTile), findsNWidgets(4));

    await tester.tap(find.text(t.watchlist.typeMovies));
    await tester.pumpAndSettle();
    expect(find.byType(OckerPosterTile), findsNWidgets(2), reason: 'only the films');
    expect(SettingsService.instance.read(SettingsService.watchlistTypeFilter), WatchlistTypeFilter.movies);

    await tester.tap(find.text(t.watchlist.typeAll));
    await tester.pumpAndSettle();
    expect(find.byType(OckerPosterTile), findsNWidgets(4));
  });

  testWidgets('under glass the panel names director and cast from the detail body it fetches anyway', (tester) async {
    final source = _FakeWatchlistSource(
      CatalogSourceId.simkl,
      'Simkl',
      detail: (item) => CatalogDetail(
        item: CatalogItem(
          source: item.source,
          kind: item.kind,
          title: item.title,
          ids: item.ids,
          overview: 'Eine Beschreibung.',
          credits: const [CatalogCredit(name: 'Regine Regie', role: CatalogCreditRole.director)],
        ),
        cast: const [
          CatalogCastMember(name: 'Anna Eins'),
          CatalogCastMember(name: 'Bert Zwei'),
          CatalogCastMember(name: 'Cora Drei'),
        ],
      ),
    );
    await _pumpWatchlist(tester, [source], variant: AppThemeVariant.glas);

    expect(find.textContaining('Regine Regie', findRichText: true), findsOneWidget);
    expect(find.textContaining('Anna Eins, Bert Zwei, Cora Drei', findRichText: true), findsOneWidget);
    expect(source.detailCastLimits, isNotEmpty);
    expect(source.detailCastLimits.toSet(), {3}, reason: 'three of the cast, from the one fetch');
  });

  testWidgets('entered while the list is still loading, the first poster takes focus once it is there', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    final gate = Completer<void>();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final source = _FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl', gate: gate.future);
    final provider = _FakeCatalogSourcesProvider([source]);
    addTearDown(provider.dispose);
    addTearDown(source.dispose);
    final libraries = _FakeLibrariesProvider(const []);
    addTearDown(libraries.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogSourcesProvider>.value(value: provider),
            ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
            home: const WatchlistScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(OckerPosterTile), findsNothing, reason: 'still loading');

    // What choosing the destination does.
    tester.state<WatchlistScreenState>(find.byType(WatchlistScreen)).focusActiveTabIfReady();
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();
    final first = tester.widget<OckerPosterTile>(find.byType(OckerPosterTile).first);
    expect(first.focusNode.hasPrimaryFocus, isTrue);
  });

  testWidgets('entering from the navigation asks for the frame it waits on', (tester) async {
    // Called at the end of a frame; without a frame of its own the cursor
    // waited for the next key press, and DOWN had to be pressed twice.
    await _pumpWatchlist(tester, [_FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl')], variant: AppThemeVariant.glas);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'settled');

    tester.state<WatchlistScreenState>(find.byType(WatchlistScreen)).focusActiveTabIfReady();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    final first = tester.widget<OckerPosterTile>(find.byType(OckerPosterTile).first);
    expect(first.focusNode.hasPrimaryFocus, isTrue, reason: 'in that one frame, not a key press later');
  });

  testWidgets('down out of the filter row reaches the redesign\'s grid', (tester) async {
    await _pumpWatchlist(tester, [_FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl')], variant: AppThemeVariant.glas);

    // The filters catch focus whenever the grid is rebuilt under it — a list
    // switch, a narrowing. With the provider switcher gone from that row,
    // DOWN is the only way back out, and it used to do nothing at all: the
    // mixin looks for the standard grid's cards, and this grid owns its own
    // focus nodes.
    final hub = tester.state<HubDetailScreenState>(find.byType(HubDetailScreen));
    hub.navigateToGrid();
    await tester.pumpAndSettle();

    final firstTile = tester.widget<OckerPosterTile>(find.byType(OckerPosterTile).first);
    expect(firstTile.focusNode.hasFocus, isTrue);
  });

  testWidgets('the redesign lists nothing in the rail for a single list', (tester) async {
    await _pumpWatchlist(tester, [_FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl')], variant: AppThemeVariant.glas);

    final state = tester.state<WatchlistScreenState>(find.byType(WatchlistScreen));
    expect(state.ockerRailMenu, isNull, reason: 'one list is not a choice');
    expect(find.byType(TabChipStrip), findsNothing);
  });

  testWidgets('the Explore tab\'s source switch does not move the watchlist', (tester) async {
    final simkl = _FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl');
    final plex = _FakeWatchlistSource(CatalogSourceId.plex, 'Plex');
    final provider = await _pumpWatchlist(tester, [simkl, plex]);

    expect(find.text('Simkl Title 0'), findsOneWidget);

    // This is what the Explore tab does when its dropdown is used.
    await provider.setActiveSource(CatalogSourceId.plex);
    await tester.pumpAndSettle();

    expect(find.text('Simkl Title 0'), findsOneWidget, reason: 'the watchlist keeps its own provider');
    expect(find.text('Plex Title 0'), findsNothing);
  });

  testWidgets('picking a chip switches the list and is remembered', (tester) async {
    await _pumpWatchlist(tester, [
      _FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl'),
      _FakeWatchlistSource(CatalogSourceId.plex, 'Plex'),
    ]);
    expect(find.text('Simkl Title 0'), findsOneWidget);

    await tester.tap(find.text('Plex'));
    await tester.pumpAndSettle();

    expect(find.text('Plex Title 0'), findsOneWidget);
    expect(find.text('Simkl Title 0'), findsNothing);
    expect(SettingsService.instance.read(SettingsService.watchlistSource), CatalogSourceId.plex.name);
  });

  testWidgets('a remembered provider is restored on open', (tester) async {
    await SettingsService.instance.write(SettingsService.watchlistSource, CatalogSourceId.plex.name);
    await _pumpWatchlist(tester, [
      _FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl'),
      _FakeWatchlistSource(CatalogSourceId.plex, 'Plex'),
    ]);

    expect(find.text('Plex Title 0'), findsOneWidget);
  });

  testWidgets('a remembered provider that is gone falls back to a connected one', (tester) async {
    await SettingsService.instance.write(SettingsService.watchlistSource, CatalogSourceId.trakt.name);
    await _pumpWatchlist(tester, [_FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl')]);

    expect(find.text('Simkl Title 0'), findsOneWidget);
  });

  testWidgets('providers without a watchlist are not offered', (tester) async {
    await _pumpWatchlist(tester, [
      _FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl'),
      _FakeWatchlistSource(CatalogSourceId.mal, 'MyAnimeList', supportsWatchlist: false),
    ]);

    expect(find.text('MyAnimeList'), findsNothing);
    expect(find.text('Simkl'), findsNothing, reason: 'one usable provider leaves nothing to switch between');
  });

  testWidgets('the whole watchlist is paged in, not just the first page', (tester) async {
    final simkl = _FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl', total: 150);
    await _pumpWatchlist(tester, [simkl]);

    expect(simkl.rowFetches.map((fetch) => fetch.$2), containsAllInOrder([1, 2]));
    expect(simkl.rowFetches.every((fetch) => fetch.$1 == CatalogRowId.watchlist), isTrue);
  });

  testWidgets('the source chips are reachable with the D-pad', (tester) async {
    await _pumpWatchlist(tester, [
      _FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl'),
      _FakeWatchlistSource(CatalogSourceId.plex, 'Plex'),
    ]);

    // The tab lands focus in the grid, UP goes to the app bar actions, and
    // LEFT out of those is the only hop into the switcher — without it the
    // chips would be focusable but unreachable.
    tester.state<WatchlistScreenState>(find.byType(WatchlistScreen)).focusActiveTabIfReady();
    await tester.pumpAndSettle();

    // The first key press is what puts the app in keyboard mode and lands
    // focus in the grid.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'detail_first_item');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'watchlist_source_1');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'watchlist_source_0');
  });

  testWidgets('a Jellyfin server adds a Favorites tab beside the providers', (tester) async {
    await _pumpWatchlist(
      tester,
      [_FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl')],
      libraries: [_library('lib-1')],
      capabilities: ServerCapabilities.jellyfin,
    );

    expect(find.text('Simkl'), findsOneWidget);
    // Named after the server, not "Favorites": beside a Plex chip the generic
    // word would not say which of the two it belongs to.
    expect(find.text('Jellyfin'), findsOneWidget);
    expect(find.text(t.libraries.filterCategories.favorites), findsNothing);
  });

  testWidgets('a Plex-only setup gets no Favorites tab', (tester) async {
    await _pumpWatchlist(
      tester,
      [_FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl')],
      libraries: [_library('lib-1')],
      capabilities: ServerCapabilities.plex,
    );

    expect(find.text('Jellyfin'), findsNothing);
    expect(find.text(t.libraries.filterCategories.favorites), findsNothing);
    // One usable list leaves nothing to switch between.
    expect(find.text('Simkl'), findsNothing);
  });

  testWidgets('the Favorites tab lists what the server marked, not the watchlist', (tester) async {
    await _pumpWatchlist(
      tester,
      [_FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl')],
      libraries: [_library('lib-1')],
      capabilities: ServerCapabilities.jellyfin,
    );
    expect(find.text('Simkl Title 0'), findsOneWidget);

    await tester.tap(find.text('Jellyfin'));
    await tester.pumpAndSettle();

    expect(find.text('Favorite 0'), findsOneWidget);
    expect(find.text('Simkl Title 0'), findsNothing);
    expect(SettingsService.instance.read(SettingsService.watchlistSource), WatchlistScreenState.favoritesTabId);
  });

  testWidgets('a title the app keeps itself stands first on its provider\'s watchlist', (tester) async {
    final kept = testMediaItem(id: 'kept-1', kind: MediaKind.show, title: 'Kept', serverId: 'server-1');
    // Stored through real async IO, outside the fake clock.
    await tester.runAsync(() async {
      await LocalWatchlist.forProfile('').add(kept, source: CatalogSourceId.simkl);
      await LocalWatchlist.forProfile('').add(
        testMediaItem(id: 'other-1', kind: MediaKind.movie, title: 'Other', serverId: 'server-1'),
        source: CatalogSourceId.trakt,
      );
    });

    await _pumpWatchlist(tester, [
      _FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl', total: 2),
    ], capabilities: ServerCapabilities.plex);

    // As the server has it now, not as it was stored.
    expect(find.text('Kept Show'), findsOneWidget);
    expect(find.text('Simkl Title 0'), findsOneWidget);
    expect(find.text('Other'), findsNothing);
    expect(tester.getTopLeft(find.text('Kept Show')).dx, lessThan(tester.getTopLeft(find.text('Simkl Title 0')).dx));
  });

  testWidgets('no connected provider leaves an empty state rather than a grid', (tester) async {
    await _pumpWatchlist(tester, const []);

    expect(find.byType(HubDetailScreen), findsNothing);
    expect(find.text(t.explore.rows.watchlist), findsOneWidget);
  });

  for (final variant in [AppThemeVariant.standard, AppThemeVariant.glas]) {
    testWidgets('on a narrow phone the type words fit the bar (${variant.name})', (tester) async {
      await _pumpWatchlist(
        tester,
        [_FakeWatchlistSource(CatalogSourceId.simkl, 'Simkl')],
        variant: variant,
        television: false,
      );
      tester.view.physicalSize = const Size(360, 780);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final word in [t.watchlist.typeAll, t.watchlist.typeMovies, t.watchlist.typeShows]) {
        expect(find.descendant(of: find.byType(FocusableActionBar), matching: find.text(word)), findsOneWidget);
        expect(tester.getRect(find.text(word)).right, lessThanOrEqualTo(360), reason: word);
      }
    });
  }

  group('narrowing the list', () {
    /// Four entries, one of each combination: an unwatched film, an unwatched
    /// series, a watched film, a watched series.
    _FakeWatchlistSource mixedSource() => _FakeWatchlistSource(
      CatalogSourceId.simkl,
      'Simkl',
      total: 4,
      shape: const [
        (kind: MediaKind.movie, watched: false),
        (kind: MediaKind.show, watched: false),
        (kind: MediaKind.movie, watched: true),
        (kind: MediaKind.show, watched: true),
      ],
    );

    /// The same glyph can sit on a poster placeholder, so an action is only
    /// ever looked for inside the app bar's own bar.
    Finder appBarAction(IconData icon) =>
        find.descendant(of: find.byType(FocusableActionBar), matching: find.byIcon(icon));

    /// The type is written out in every look: one word per choice.
    Future<void> pickType(WidgetTester tester, String word) async {
      await tester.tap(find.descendant(of: find.byType(FocusableActionBar), matching: find.text(word)));
      await tester.pumpAndSettle();
    }

    Future<void> pick(WidgetTester tester, IconData action, String option) async {
      await tester.tap(appBarAction(action));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option));
      await tester.pumpAndSettle();
    }

    testWidgets('one kind at a time', (tester) async {
      await _pumpWatchlist(tester, [mixedSource()]);
      expect(find.text('Simkl Title 1'), findsOneWidget);

      await pickType(tester, t.watchlist.typeMovies);

      expect(find.text('Simkl Title 0'), findsOneWidget, reason: 'a film');
      expect(find.text('Simkl Title 2'), findsOneWidget, reason: 'a film, watched');
      expect(find.text('Simkl Title 1'), findsNothing, reason: 'a series');
      expect(find.text('Simkl Title 3'), findsNothing, reason: 'a series');

      await pickType(tester, t.watchlist.typeShows);

      expect(find.text('Simkl Title 1'), findsOneWidget);
      expect(find.text('Simkl Title 0'), findsNothing);
    });

    testWidgets('watched, unwatched, or both', (tester) async {
      await _pumpWatchlist(tester, [mixedSource()]);

      await pick(tester, Symbols.filter_alt_rounded, t.watchlist.unwatchedOnly);
      expect(find.text('Simkl Title 0'), findsOneWidget);
      expect(find.text('Simkl Title 2'), findsNothing, reason: 'watched');

      await pick(tester, Symbols.visibility_off_rounded, t.watchlist.watchedOnly);
      expect(find.text('Simkl Title 2'), findsOneWidget);
      expect(find.text('Simkl Title 0'), findsNothing, reason: 'not watched yet');

      await pick(tester, Symbols.visibility_rounded, t.watchlist.anyStatus);
      expect(find.text('Simkl Title 0'), findsOneWidget);
      expect(find.text('Simkl Title 2'), findsOneWidget);
    });

    testWidgets('the two halves narrow together', (tester) async {
      await _pumpWatchlist(tester, [mixedSource()]);

      await pickType(tester, t.watchlist.typeShows);
      await pick(tester, Symbols.filter_alt_rounded, t.watchlist.watchedOnly);

      expect(find.text('Simkl Title 3'), findsOneWidget, reason: 'the watched series');
      for (final other in ['Simkl Title 0', 'Simkl Title 1', 'Simkl Title 2']) {
        expect(find.text(other), findsNothing);
      }
    });

    testWidgets('a narrowing that hides everything says so', (tester) async {
      await _pumpWatchlist(tester, [
        _FakeWatchlistSource(
          CatalogSourceId.simkl,
          'Simkl',
          total: 2,
          shape: const [(kind: MediaKind.movie, watched: false)],
        ),
      ]);

      await pickType(tester, t.watchlist.typeShows);

      expect(find.text(t.libraries.noItemsMatchFilters), findsOneWidget);
      expect(find.text(t.hubDetail.noItemsFound), findsNothing, reason: 'the list is not empty, the filter is strict');
    });

    testWidgets('narrowing does not fetch the list again', (tester) async {
      final source = mixedSource();
      await _pumpWatchlist(tester, [source]);
      final fetchesBefore = source.rowFetches.length;

      await pickType(tester, t.watchlist.typeMovies);

      expect(source.rowFetches.length, fetchesBefore, reason: 'the answer is already on screen');
    });

    testWidgets('a narrowing is remembered', (tester) async {
      await _pumpWatchlist(tester, [mixedSource()]);

      await pickType(tester, t.watchlist.typeShows);

      expect(SettingsService.instance.read(SettingsService.watchlistTypeFilter), WatchlistTypeFilter.shows);
      expect(SettingsService.instance.read(SettingsService.watchlistStatusFilter), WatchlistStatusFilter.any);
    });

    testWidgets('a remembered narrowing is in force on open', (tester) async {
      await SettingsService.instance.write(SettingsService.watchlistTypeFilter, WatchlistTypeFilter.shows);
      await SettingsService.instance.write(SettingsService.watchlistStatusFilter, WatchlistStatusFilter.watched);

      await _pumpWatchlist(tester, [mixedSource()]);

      expect(find.text('Simkl Title 3'), findsOneWidget);
      expect(find.text('Simkl Title 0'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.selected == true &&
              widget.properties.label == t.watchlist.typeShows,
        ),
        findsOneWidget,
        reason: 'the word on show is marked',
      );
      expect(appBarAction(Symbols.visibility_rounded), findsOneWidget);
    });

    testWidgets('switching provider keeps the narrowing', (tester) async {
      await _pumpWatchlist(tester, [
        mixedSource(),
        _FakeWatchlistSource(
          CatalogSourceId.plex,
          'Plex',
          total: 2,
          shape: const [(kind: MediaKind.movie, watched: false), (kind: MediaKind.show, watched: false)],
        ),
      ]);

      await pickType(tester, t.watchlist.typeShows);
      await tester.tap(find.text('Plex'));
      await tester.pumpAndSettle();

      expect(find.text('Plex Title 1'), findsOneWidget, reason: 'the series');
      expect(find.text('Plex Title 0'), findsNothing, reason: 'the film');
    });
  });
}
