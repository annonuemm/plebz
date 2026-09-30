import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:plezy/focus/focusable_action_bar.dart';
import 'package:plezy/i18n/app_locale_utils.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_part.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/media_stream.dart';
import 'package:plezy/services/catalog/library_copy_quality_loader.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/models/catalog/catalog_cast_member.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/models/catalog/catalog_metadata.dart';
import 'package:plezy/models/seerr/seerr_session.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/seerr_account_provider.dart';
import 'package:plezy/screens/catalog_item_detail_screen.dart';
import 'package:plezy/widgets/detail_home_button.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/catalog/catalog_library_matcher.dart';
import 'package:plezy/services/catalog/seerr_catalog_source.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/seerr/seerr_client.dart';
import 'package:plezy/services/seerr/seerr_auth_service.dart';
import 'package:plezy/services/seerr/seerr_constants.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/library_copy_jump_button.dart';
import 'package:plezy/widgets/library_copy_tile.dart';
import 'package:plezy/widgets/corner_backdrop.dart';
import 'package:plezy/widgets/overlay_sheet.dart';
import 'package:plezy/widgets/hub_section.dart';
import 'package:plezy/widgets/focusable_list_tile.dart';
import 'package:plezy/widgets/media_card.dart';
import 'package:plezy/widgets/optimized_media_image.dart';
import 'package:provider/provider.dart';

import 'package:intl/intl.dart';
import 'package:plezy/models/catalog/catalog_labels.dart';
import 'package:plezy/widgets/stat_chip.dart';
import 'package:plezy/widgets/focusable_tab_chip.dart';
import '../test_helpers/library_lookup.dart';
import '../test_helpers/media_items.dart';
import '../test_helpers/paged_fakes.dart';
import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';

class _FakeCatalogSource implements CatalogSource {
  final WatchlistChangeNotifier _watchlistChanges = WatchlistChangeNotifier();
  _FakeCatalogSource({
    bool watchlistLoading = false,
    this.watchlistUnreadable = false,
    this.supportsWatchlist = true,
    this.detail,
    this.detailError,
    this.detailCompleter,
  }) : _watchlistValue = (watchlistLoading || watchlistUnreadable) ? null : false,
       _watchlistLoad = watchlistLoading ? Completer<void>() : null;

  /// The provider answers, but never with a membership — Plex Discover
  /// returning 504 for the watchlist snapshot, which it does often enough to
  /// be ordinary.
  final bool watchlistUnreadable;

  bool? _watchlistValue;
  final Completer<void>? _watchlistLoad;
  int addToWatchlistCalls = 0;

  final CatalogDetail? detail;
  final Object? detailError;
  final Completer<CatalogDetail>? detailCompleter;
  int fetchDetailCalls = 0;
  @override
  CatalogSourceId get id => CatalogSourceId.trakt;

  @override
  String get displayName => 'Trakt';

  @override
  final bool supportsWatchlist;

  @override
  Listenable get watchlistChanges => _watchlistChanges;

  @override
  Future<CatalogDetail> fetchDetail(CatalogItem item, {int castLimit = 20, int relatedLimit = 20}) async {
    fetchDetailCalls++;
    final completer = detailCompleter;
    if (completer != null) return completer.future;
    final error = detailError;
    if (error != null) throw error;
    return detail ??
        CatalogDetail(
          item: item,
          cast: const [
            CatalogCastMember(name: 'First Actor', secondary: 'Lead'),
            CatalogCastMember(name: 'Second Actor', secondary: 'Support'),
          ],
          related: const [
            CatalogItem(
              source: CatalogSourceId.trakt,
              kind: MediaKind.movie,
              title: 'Related Movie',
              ids: CatalogItemIds(tmdb: 2),
            ),
          ],
        );
  }

  @override
  Future<void> ensureWatchlistLoaded() async {
    final load = _watchlistLoad;
    if (load != null) await load.future;
  }

  void completeWatchlistLoad() {
    _watchlistValue = false;
    _watchlistChanges.notify();
    _watchlistLoad!.complete();
  }

  @override
  Future<void> addToWatchlist(MediaKind kind, CatalogItemIds ids, {String? title}) async {
    addToWatchlistCalls++;
    if (watchlistUnreadable) return;
    _watchlistValue = true;
    _watchlistChanges.notify();
  }

  @override
  bool? isOnWatchlist(MediaKind kind, CatalogItemIds ids) => _watchlistValue;

  @override
  void dispose() => _watchlistChanges.dispose();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCatalogSourcesProvider extends CatalogSourcesProvider {
  final CatalogSource source;
  SeerrCatalogSource? seerr;

  _FakeCatalogSourcesProvider(this.source, {this.seerr});

  @override
  List<CatalogSource> get connectedSources => [source, ?seerr];

  @override
  SeerrCatalogSource? get seerrSource => seerr;

  /// Mirrors the proxy update production runs on every account notify: the
  /// Seerr source follows the client's identity, so a disconnect drops it
  /// (and notifies) while an in-place permission adoption changes nothing.
  void followAccount(SeerrAccountProvider account) {
    _ownsSeerr = true;
    _bindClient(account.catalogClient);
    account.addListener(() => _bindClient(account.catalogClient));
  }

  bool _ownsSeerr = false;

  void _bindClient(SeerrClient? client) {
    if (client == seerr?.client) return;
    seerr?.dispose();
    seerr = client == null ? null : SeerrCatalogSource(client);
    notifyListeners();
  }

  @override
  void dispose() {
    if (_ownsSeerr) seerr?.dispose();
    super.dispose();
  }
}

/// A live [SeerrAccountProvider] bound to [permissions], whose client answers
/// `/auth/me` with the current value of [permissions] so a test can land a
/// grant or revocation through the provider's own refresh path.
Future<SeerrAccountProvider> _seerrAccount(int Function() permissions) async {
  final mock = MockClient((request) async {
    if (request.url.path != '/api/v1/auth/me') return http.Response('unexpected Seerr request', 500);
    return http.Response(
      jsonEncode({'id': 1, 'displayName': 'Alice', 'permissions': permissions()}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  final account = SeerrAccountProvider(authService: SeerrAuthService(httpClientFactory: () => mock));
  addTearDown(account.dispose);
  await account.adoptSession(
    SeerrSession(
      baseUrl: 'https://seerr.example.com',
      method: SeerrAuthMethod.local,
      identifier: 'a@b.c',
      secret: '',
      cookie: 'cookie',
      userId: 1,
      permissions: permissions(),
      displayName: 'Alice',
      instanceLabel: 'Seerr',
      createdAt: 0,
    ),
  );
  return account;
}

/// A real [SeerrCatalogSource]: the Request gate reads the session's
/// permission bitmask through [SeerrCatalogSource.canRequest]. None of these
/// tests open the request sheet, so no Seerr HTTP is expected.
SeerrCatalogSource _seerrSource({int permissions = SeerrPermission.request}) {
  final client = SeerrClient(
    SeerrSession(
      baseUrl: 'https://seerr.example.com',
      method: SeerrAuthMethod.local,
      identifier: 'a@b.c',
      secret: 'pw',
      cookie: 'cookie',
      userId: 1,
      permissions: permissions,
      displayName: 'Alice',
      instanceLabel: 'Seerr',
      createdAt: 0,
    ),
    onSessionInvalidated: () {},
    httpClient: MockClient((request) async => http.Response('unexpected Seerr request', 500)),
  );
  final source = SeerrCatalogSource(client);
  addTearDown(() {
    source.dispose();
    client.dispose();
  });
  return source;
}

/// A Seerr source whose signed-in user may request anything.
SeerrCatalogSource _requestingSeerr() => SeerrCatalogSource(
  SeerrClient(
    SeerrSession(
      baseUrl: 'https://seerr.example.com',
      method: SeerrAuthMethod.local,
      identifier: 'a@b.c',
      secret: 'x',
      cookie: 'c',
      userId: 1,
      // Admin, which implies every request permission.
      permissions: 2,
      displayName: 'Alice',
      instanceLabel: 'Seerr',
      createdAt: 0,
    ),
    onSessionInvalidated: () {},
    httpClient: MockClient((_) async => http.Response('{}', 200)),
  ),
);

class _FakeCatalogLibraryMatcher extends CatalogLibraryMatcher {
  _FakeCatalogLibraryMatcher(super.multiServer, this.matches);

  final List<MediaItem> matches;

  @override
  Future<LibraryLookupResult> match(CatalogItem item) async => libraryLookupResult(matches);
}

/// Matches only items that carry an external id, the way a real lookup for a
/// Plex Discover row does (#1715): the bare rating-key form misses, the
/// detail-enriched form hits.
class _ExternalIdGatedMatcher extends CatalogLibraryMatcher {
  _ExternalIdGatedMatcher(super.multiServer, this.hit);

  final MediaItem hit;
  final List<CatalogItem> calls = [];

  @override
  Future<LibraryLookupResult> match(CatalogItem item) async {
    calls.add(item);
    return libraryLookupResult(item.ids.toExternalIds().hasAny ? [hit] : const []);
  }
}

/// Serves one scripted result per `match` call, so a test can model the bare
/// row lookup and the detail-enriched lookup independently.
class _ScriptedMatcher extends CatalogLibraryMatcher {
  _ScriptedMatcher(super.multiServer, this.passes);

  final List<FutureOr<LibraryLookupResult> Function()> passes;
  int calls = 0;

  @override
  Future<LibraryLookupResult> match(CatalogItem item) async {
    final pass = passes[calls < passes.length ? calls : passes.length - 1];
    calls++;
    return pass();
  }
}

/// A Plex Discover row whose bare form carries only its own id; the detail
/// body adds the external ids (#1715), which is what triggers a second pass.
const _bareRow = CatalogItem(
  source: CatalogSourceId.trakt,
  kind: MediaKind.movie,
  title: 'Row-only Movie',
  ids: CatalogItemIds(trakt: 5),
);
const _enrichedRow = CatalogItem(
  source: CatalogSourceId.trakt,
  kind: MediaKind.movie,
  title: 'Row-only Movie',
  ids: CatalogItemIds(trakt: 5, tmdb: 99),
);

MediaItem _libraryCopy({
  required String id,
  String? libraryTitle,
  String? videoResolution,
  String? serverName = 'Living Room',
}) => testMediaItem(
  id: id,
  serverId: 'server-1',
  serverName: serverName,
  libraryId: libraryTitle == null ? null : id,
  libraryTitle: libraryTitle,
  mediaVersions: videoResolution == null
      ? null
      : [MediaVersion(id: '$id-v', videoResolution: videoResolution, videoCodec: 'hevc', container: 'mkv')],
);

const _item = CatalogItem(
  source: CatalogSourceId.trakt,
  kind: MediaKind.movie,
  title: 'Catalog Movie',
  overview: 'Overview',
  ids: CatalogItemIds(tmdb: 1),
);

String _dateOf(DateTime date) => DateFormat.yMMMd(LocaleSettings.currentLocale.intlLocaleName).format(date.toLocal());

/// The meta line under the title, told apart from the fact grid below (which
/// lists the release date on its own) by the runtime that follows it.
Finder _metaLineStartingWith(String text) => find.textContaining(RegExp('^${RegExp.escape(text)} •'));

Future<void> _pumpDetail(
  WidgetTester tester,
  _FakeCatalogSource source, {
  List<MediaItem> matches = const [],
  bool pushedRoute = false,
  CatalogItem item = _item,
  CatalogLibraryMatcher Function(MultiServerProvider multiServer)? matcherBuilder,
  SeerrCatalogSource? seerr,
  SeerrAccountProvider? account,
  bool settle = true,
  List<MediaServerClient> clients = const [],
  void Function(MediaItem copy)? onOpenLibraryCopy,
}) async {
  final sources = _FakeCatalogSourcesProvider(source, seerr: seerr);
  if (account != null) sources.followAccount(account);
  final serverManager = MultiServerManager();
  for (final client in clients) {
    serverManager.debugRegisterClientForTesting(client);
  }
  final multiServer = testMultiServerProvider(serverManager);
  final matcher = matcherBuilder?.call(multiServer) ?? _FakeCatalogLibraryMatcher(multiServer, matches);
  addTearDown(sources.dispose);
  addTearDown(source.dispose);
  addTearDown(serverManager.dispose);
  addTearDown(multiServer.dispose);
  addTearDown(matcher.dispose);
  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          Provider<CatalogLibraryMatcher>.value(value: matcher),
          ChangeNotifierProvider<CatalogSourcesProvider>.value(value: sources),
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          if (account != null) ChangeNotifierProvider<SeerrAccountProvider>.value(value: account),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: pushedRoute
              ? Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CatalogItemDetailScreen(item: item, onOpenLibraryCopy: onOpenLibraryCopy),
                        ),
                      ),
                      child: const Text('Open catalog'),
                    ),
                  ),
                )
              : CatalogItemDetailScreen(item: item, onOpenLibraryCopy: onOpenLibraryCopy),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  if (pushedRoute) {
    await tester.tap(find.text('Open catalog'));
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    // The facts section formats dates; `main.dart` does this at startup.
    await initializeDateFormatting('en');
  });

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  setUp(LibraryCopyQualityLoader.clearForTesting);

  group('best copy', _bestCopyTests);

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  group('the home button', () {
    testWidgets('stands alone in the corner on a television, up from the actions and back down', (tester) async {
      final source = _FakeCatalogSource(detail: const CatalogDetail(item: _item));
      await _pumpDetail(tester, source);

      expect(find.byType(DetailHomeButton), findsOneWidget);
      expect(find.byType(DetailHomeBesideBack), findsNothing, reason: 'no back arrow on a television');
      final firstAction = FocusManager.instance.primaryFocus;
      expect(
        firstAction?.context?.findAncestorWidgetOfExactType<FocusableActionBar>(),
        isNotNull,
        reason: 'the page opens on its actions',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_detail_home');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(firstAction));
    });

    testWidgets('stands beside the back arrow off a television', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(false);
      final source = _FakeCatalogSource(detail: const CatalogDetail(item: _item));
      await _pumpDetail(tester, source, pushedRoute: true);

      expect(find.byType(DetailHomeBesideBack), findsOneWidget);
      expect(find.byType(DetailHomeButton), findsNothing);
    });
  });

  group('release date in the meta line', () {
    testWidgets('a title from this year carries the day, not just the year', (tester) async {
      final thisYear = DateTime(DateTime.now().year, 3, 14);
      final item = CatalogItem(
        source: CatalogSourceId.trakt,
        kind: MediaKind.movie,
        title: 'Catalog Movie',
        year: thisYear.year,
        ids: const CatalogItemIds(tmdb: 603),
        runtimeMinutes: 150,
        releaseDate: thisYear,
      );
      final source = _FakeCatalogSource(detail: CatalogDetail(item: item));

      await _pumpDetail(tester, source, item: item);

      // "2026" alone says nothing about whether it is out yet, which for a
      // title from this year is exactly what is being asked.
      expect(_metaLineStartingWith(_dateOf(thisYear)), findsOneWidget);
    });

    testWidgets('an older title keeps the bare year', (tester) async {
      final old = DateTime(DateTime.now().year - 3, 3, 14);
      final item = CatalogItem(
        source: CatalogSourceId.trakt,
        kind: MediaKind.movie,
        title: 'Catalog Movie',
        year: old.year,
        ids: const CatalogItemIds(tmdb: 603),
        runtimeMinutes: 150,
        releaseDate: old,
      );
      final source = _FakeCatalogSource(detail: CatalogDetail(item: item));

      await _pumpDetail(tester, source, item: item);

      expect(_metaLineStartingWith('${old.year}'), findsOneWidget);
      expect(_metaLineStartingWith(_dateOf(old)), findsNothing);
    });
  });

  testWidgets('a refused request is marked in the accent, not left in the quiet fill', (tester) async {
    const declined = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Catalog Movie',
      ids: CatalogItemIds(tmdb: 603),
      serverState: CatalogServerState(request: CatalogRequestState.declined),
    );
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: declined));

    await _pumpDetail(tester, source, item: declined);

    final chip = tester.widget<StatChip>(
      find.widgetWithText(StatChip, requestStateLabel(CatalogRequestState.declined, is4k: false)),
    );
    // It is the reason the title is not coming; it should not read as one
    // more fact among the ratings and the runtime.
    expect(chip.backgroundColor, activeTabChipColor);
    expect(chip.labelColor, Colors.white);
  });

  testWidgets('a request still pending keeps the quiet fill', (tester) async {
    const pending = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Catalog Movie',
      ids: CatalogItemIds(tmdb: 603),
      serverState: CatalogServerState(request: CatalogRequestState.pending),
    );
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: pending));

    await _pumpDetail(tester, source, item: pending);

    final chip = tester.widget<StatChip>(
      find.widgetWithText(StatChip, requestStateLabel(CatalogRequestState.pending, is4k: false)),
    );
    expect(chip.backgroundColor, isNull);
  });

  group('backdrop treatment', () {
    const withArt = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Catalog Movie',
      overview: 'Overview',
      ids: CatalogItemIds(tmdb: 1),
      backdropUrl: 'https://images.example/backdrop.jpg',
    );

    group('request action', () {
      const plexRow = CatalogItem(
        source: CatalogSourceId.trakt,
        kind: MediaKind.movie,
        title: 'Catalog Movie',
        overview: 'Overview',
        // What a Plex Discover row carries: its own key, no external ids.
        ids: CatalogItemIds(plex: '5d9c0874'),
      );

      testWidgets('appears once the detail body supplies the TMDB id', (tester) async {
        final source = _FakeCatalogSource(
          detail: const CatalogDetail(
            item: CatalogItem(
              source: CatalogSourceId.trakt,
              kind: MediaKind.movie,
              title: 'Catalog Movie',
              ids: CatalogItemIds(plex: '5d9c0874', tmdb: 603),
            ),
          ),
        );

        await _pumpDetail(tester, source, item: plexRow, seerr: _requestingSeerr());

        // Decided at open time on the thin row, the action would never appear
        // for a Plex Discover title.
        expect(find.byTooltip(t.seerr.request), findsOneWidget);
      });

      testWidgets('stays away for a title already on the server', (tester) async {
        const onServer = CatalogItem(
          source: CatalogSourceId.trakt,
          kind: MediaKind.movie,
          title: 'Catalog Movie',
          ids: CatalogItemIds(tmdb: 603),
          serverState: CatalogServerState(availability: CatalogAvailability.available),
        );
        final source = _FakeCatalogSource(detail: const CatalogDetail(item: onServer));

        await _pumpDetail(tester, source, item: onServer, seerr: _requestingSeerr());

        // Nothing left to ask for; the page says "available" in its own line.
        expect(find.byTooltip(t.seerr.request), findsNothing);
      });

      testWidgets('stays for a series the server holds only part of', (tester) async {
        const partly = CatalogItem(
          source: CatalogSourceId.trakt,
          kind: MediaKind.show,
          title: 'Catalog Show',
          ids: CatalogItemIds(tmdb: 1396),
          serverState: CatalogServerState(
            availability: CatalogAvailability.partiallyAvailable,
            availableSeasons: 2,
            totalSeasons: 5,
          ),
        );
        final source = _FakeCatalogSource(detail: const CatalogDetail(item: partly));

        await _pumpDetail(tester, source, item: partly, seerr: _requestingSeerr());

        // The three seasons that are missing are exactly what a request is for.
        expect(find.byTooltip(t.seerr.request), findsOneWidget);
      });

      testWidgets('stays for a title the provider says nothing about', (tester) async {
        const unknown = CatalogItem(
          source: CatalogSourceId.trakt,
          kind: MediaKind.movie,
          title: 'Catalog Movie',
          ids: CatalogItemIds(tmdb: 603),
        );
        final source = _FakeCatalogSource(detail: const CatalogDetail(item: unknown));

        await _pumpDetail(tester, source, item: unknown, seerr: _requestingSeerr());

        // Most providers know nothing about your server; silence is not
        // availability, and reading it as such would hide the action wherever
        // Seerr is not the source.
        expect(find.byTooltip(t.seerr.request), findsOneWidget);
      });

      testWidgets('stays away for a title that is not out yet', (tester) async {
        final unreleased = CatalogItem(
          source: CatalogSourceId.trakt,
          kind: MediaKind.movie,
          title: 'Catalog Movie',
          ids: const CatalogItemIds(tmdb: 603),
          runtimeMinutes: 150,
          releaseDate: DateTime.now().add(const Duration(days: 40)),
        );
        final source = _FakeCatalogSource(detail: CatalogDetail(item: unreleased));

        await _pumpDetail(tester, source, item: unreleased, seerr: _requestingSeerr());

        expect(find.byTooltip(t.seerr.request), findsNothing);
        // The reason stands where the action would have been: a bare year
        // says nothing about whether a title is out yet.
        expect(_metaLineStartingWith(_dateOf(unreleased.releaseDate!)), findsOneWidget);
      });

      testWidgets('stays away for the first week after a release', (tester) async {
        final justOut = CatalogItem(
          source: CatalogSourceId.trakt,
          kind: MediaKind.movie,
          title: 'Catalog Movie',
          ids: const CatalogItemIds(tmdb: 603),
          runtimeMinutes: 150,
          releaseDate: DateTime.now().subtract(const Duration(days: 3)),
        );
        final source = _FakeCatalogSource(detail: CatalogDetail(item: justOut));

        await _pumpDetail(tester, source, item: justOut, seerr: _requestingSeerr());

        // Nothing reaches a server the day it comes out.
        expect(find.byTooltip(t.seerr.request), findsNothing);
        expect(_metaLineStartingWith(_dateOf(justOut.releaseDate!)), findsOneWidget);
      });

      testWidgets('appears once the release is a week behind it', (tester) async {
        final outAWhile = CatalogItem(
          source: CatalogSourceId.trakt,
          kind: MediaKind.movie,
          title: 'Catalog Movie',
          ids: const CatalogItemIds(tmdb: 603),
          releaseDate: DateTime.now().subtract(const Duration(days: 8)),
        );
        final source = _FakeCatalogSource(detail: CatalogDetail(item: outAWhile));

        await _pumpDetail(tester, source, item: outAWhile, seerr: _requestingSeerr());

        expect(find.byTooltip(t.seerr.request), findsOneWidget);
      });

      testWidgets('stays away for a film the app itself found in a library', (tester) async {
        // Seerr lines libraries up by TMDB id through its own scan, so a film
        // Plex matched to a different id reads as missing there while sitting
        // in the library all the same. What the app found first-hand wins.
        const missedByProvider = CatalogItem(
          source: CatalogSourceId.trakt,
          kind: MediaKind.movie,
          title: 'Catalog Movie',
          ids: CatalogItemIds(tmdb: 603),
          serverState: CatalogServerState(availability: CatalogAvailability.unavailable),
        );
        final source = _FakeCatalogSource(detail: const CatalogDetail(item: missedByProvider));

        await _pumpDetail(
          tester,
          source,
          item: missedByProvider,
          seerr: _requestingSeerr(),
          matches: [testMediaItem(id: 'plex-1', title: 'Catalog Movie')],
        );

        expect(find.byTooltip(t.seerr.request), findsNothing);
        // And the page says so outright. The provider has no word for "not
        // here" — without this, a copy it missed looks exactly like a copy
        // that does not exist.
        expect(find.text(availabilityLabel(CatalogAvailability.available, is4k: false)!), findsOneWidget);
      });

      testWidgets('stays for a series the app found, which may still lack seasons', (tester) async {
        const show = CatalogItem(
          source: CatalogSourceId.trakt,
          kind: MediaKind.show,
          title: 'Catalog Show',
          ids: CatalogItemIds(tmdb: 1396),
          serverState: CatalogServerState(availability: CatalogAvailability.unavailable),
        );
        final source = _FakeCatalogSource(detail: const CatalogDetail(item: show));

        await _pumpDetail(
          tester,
          source,
          item: show,
          seerr: _requestingSeerr(),
          matches: [testMediaItem(id: 'plex-2', kind: MediaKind.show, title: 'Catalog Show')],
        );

        expect(find.byTooltip(t.seerr.request), findsOneWidget);
      });

      testWidgets('stays away when nothing supplies an id', (tester) async {
        final source = _FakeCatalogSource(detail: const CatalogDetail(item: plexRow));

        await _pumpDetail(tester, source, item: plexRow, seerr: _requestingSeerr());

        expect(find.byTooltip(t.seerr.request), findsNothing);
      });

      testWidgets('stays away without a Seerr connection', (tester) async {
        final source = _FakeCatalogSource(
          detail: const CatalogDetail(
            item: CatalogItem(
              source: CatalogSourceId.trakt,
              kind: MediaKind.movie,
              title: 'Catalog Movie',
              ids: CatalogItemIds(tmdb: 603),
            ),
          ),
        );

        await _pumpDetail(tester, source, item: plexRow);

        expect(find.byTooltip(t.seerr.request), findsNothing);
      });
    });

    testWidgets('a full-width strip by default', (tester) async {
      final source = _FakeCatalogSource();

      await _pumpDetail(tester, source, item: withArt);

      expect(find.byType(CornerBackdrop), findsNothing);
    });

    testWidgets('follows the corner setting the TV spotlight uses', (tester) async {
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.tvCornerSpotlightBackdrop, true);
      final source = _FakeCatalogSource();

      // Reached straight from Explore, so it would jar if the artwork
      // treatment changed on the way in.
      await _pumpDetail(tester, source, item: withArt);

      expect(find.byType(CornerBackdrop), findsOneWidget);
    });

    testWidgets('nothing to place when the item has no artwork', (tester) async {
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.tvCornerSpotlightBackdrop, true);
      final source = _FakeCatalogSource();

      await _pumpDetail(tester, source);

      expect(find.byType(CornerBackdrop), findsNothing);
    });
  });

  testWidgets('fetchDetail replaces the opening item with its enriched item once loaded', (tester) async {
    final detailCompleter = Completer<CatalogDetail>();
    final source = _FakeCatalogSource(detailCompleter: detailCompleter);

    await _pumpDetail(tester, source);
    expect(find.text('Catalog Movie'), findsOneWidget);
    expect(find.text('Enriched overview'), findsNothing);

    detailCompleter.complete(
      const CatalogDetail(
        item: CatalogItem(
          source: CatalogSourceId.trakt,
          kind: MediaKind.movie,
          title: 'Enriched Catalog Movie',
          overview: 'Enriched overview',
          ids: CatalogItemIds(tmdb: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(source.fetchDetailCalls, 1);
    expect(find.text('Enriched Catalog Movie'), findsOneWidget);
    expect(find.text('Enriched overview'), findsOneWidget);
    expect(find.text('Catalog Movie'), findsNothing);
  });

  testWidgets('detail enrichment that adds external ids re-resolves library matches', (tester) async {
    // #1715: the row form of a Plex Discover item carries only its rating
    // key and the first lookup misses; the detail body brings the external
    // ids, which must trigger a second lookup instead of leaving the screen
    // on "Not in your library".
    const bare = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Row-only Movie',
      ids: CatalogItemIds(trakt: 5),
    );
    const enriched = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Row-only Movie',
      ids: CatalogItemIds(trakt: 5, tmdb: 99),
    );
    final hit = testMediaItem(id: 'server-match', libraryTitle: 'Movies', serverName: 'Living Room');
    late _ExternalIdGatedMatcher matcher;
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: enriched));

    await _pumpDetail(
      tester,
      source,
      item: bare,
      matcherBuilder: (multiServer) => matcher = _ExternalIdGatedMatcher(multiServer, hit),
    );

    expect(matcher.calls.map((call) => call.ids.tmdb), [null, 99]);
    expect(find.text(t.explore.notInLibrary), findsNothing);
    expect(find.text(t.explore.inTheseLibraries), findsOneWidget);
    expect(_copyRow('Movies'), findsOneWidget);
  });

  testWidgets('detail enrichment that adds the native title re-resolves library matches', (tester) async {
    // #2098: a row item without originalTitle gains it from the detail load,
    // and a romaji-filed copy is reachable only through it. Same ids, so the
    // id-based trigger alone would not re-ask.
    const bare = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.show,
      title: "Frieren: Beyond Journey's End",
      ids: CatalogItemIds(trakt: 198225, tvdb: 424536),
    );
    const enriched = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.show,
      title: "Frieren: Beyond Journey's End",
      originalTitle: '葬送のフリーレン',
      ids: CatalogItemIds(trakt: 198225, tvdb: 424536),
    );
    late _ScriptedMatcher matcher;
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: enriched));

    await _pumpDetail(
      tester,
      source,
      item: bare,
      matcherBuilder: (multiServer) => matcher = _ScriptedMatcher(multiServer, [
        () => libraryLookupResult(const [], succeeded: {'server-1'}),
        () => libraryLookupResult([_libraryCopy(id: 'romaji-copy', libraryTitle: 'Anime (romaji)')]),
      ]),
    );

    expect(matcher.calls, 2);
    expect(find.text(t.explore.notInLibrary), findsNothing);
    expect(_copyRow('Anime (romaji)'), findsOneWidget);
  });

  group('Seerr request action', () {
    testWidgets('appears once the detail load supplies the tmdb id', (tester) async {
      // #1959: Plex Discover's hub/search/related endpoints ignore
      // includeGuids, so a row item carries no tmdb id until fetchDetail
      // brings one. The Request gate must read the enriched item, not the
      // row form the screen opened with.
      final detailCompleter = Completer<CatalogDetail>();
      final source = _FakeCatalogSource(detailCompleter: detailCompleter);

      await _pumpDetail(tester, source, item: _bareRow, seerr: _seerrSource());
      expect(find.byTooltip(t.seerr.request), findsNothing);

      detailCompleter.complete(const CatalogDetail(item: _enrichedRow));
      await tester.pumpAndSettle();

      expect(find.byTooltip(t.seerr.request), findsOneWidget);
    });

    testWidgets('appears immediately when the row item already carries a tmdb id', (tester) async {
      final source = _FakeCatalogSource();

      await _pumpDetail(tester, source, seerr: _seerrSource());

      expect(find.byTooltip(t.seerr.request), findsOneWidget);
    });

    testWidgets('stays hidden without the request permission', (tester) async {
      final source = _FakeCatalogSource();

      // A mask that says something, and does not say "request". Zero is not
      // that: this fork reads an all-zero mask as "the instance did not tell
      // us" and lets the action through, because some Seerr deployments
      // report no bits at all.
      await _pumpDetail(tester, source, seerr: _seerrSource(permissions: SeerrPermission.request4k));

      expect(find.byTooltip(t.seerr.request), findsNothing);
    });

    testWidgets('an empty permission mask hides the action rather than guessing', (tester) async {
      // It used to mean "this instance told us nothing" — POST /auth/local
      // answers with the entity default (#2213). The sign-in reads
      // GET /auth/me now, so a zero mask is a real answer: no permission.
      final source = _FakeCatalogSource();

      await _pumpDetail(tester, source, seerr: _seerrSource(permissions: 0));

      expect(find.byTooltip(t.seerr.request), findsNothing);
    });

    testWidgets('follows a permission grant and revocation the account adopts while open', (tester) async {
      // The account refresh used on foreground adopts a changed mask in place:
      // the client is never replaced, so eligibility must be derived live.
      // The provider persists every adoption, and the prefs store only
      // completes under real async.
      var permissions = 0;
      final account = (await tester.runAsync(() => _seerrAccount(() => permissions)))!;

      await _pumpDetail(tester, _FakeCatalogSource(), account: account);
      expect(find.byTooltip(t.seerr.request), findsNothing);

      permissions = SeerrPermission.request;
      await tester.runAsync(account.refreshUser);
      await tester.pump();
      expect(find.byTooltip(t.seerr.request), findsOneWidget);

      permissions = 0;
      await tester.runAsync(account.refreshUser);
      await tester.pump();
      expect(find.byTooltip(t.seerr.request), findsNothing);
    });

    testWidgets('disappears when the account disconnects while open', (tester) async {
      final account = (await tester.runAsync(() => _seerrAccount(() => SeerrPermission.request)))!;

      await _pumpDetail(tester, _FakeCatalogSource(), account: account);
      expect(find.byTooltip(t.seerr.request), findsOneWidget);

      await tester.runAsync(account.disconnect);
      await tester.pump();

      expect(find.byTooltip(t.seerr.request), findsNothing);
    });
  });

  testWidgets('lists every library copy of one title, best quality first', (tester) async {
    // #1754: one movie held by both a 4K library and an HD library on the same
    // server. Library names are user-chosen, so each row also states the
    // resolution the user is actually choosing between.
    final source = _FakeCatalogSource();

    await _pumpDetail(
      tester,
      source,
      matches: [
        _libraryCopy(id: 'hd-copy', libraryTitle: 'Movies', videoResolution: '1080'),
        _libraryCopy(id: 'uhd-copy', libraryTitle: '4K Movies', videoResolution: '4k'),
      ],
    );

    expect(find.text(t.explore.inTheseLibraries), findsOneWidget);
    expect(_copyRow('Movies'), findsOneWidget);
    expect(_copyRow('4K Movies'), findsOneWidget);

    final subtitles = tester.widgetList<Text>(find.textContaining('Living Room')).map((text) => text.data!).toList();
    expect(subtitles, hasLength(2));
    expect(subtitles.first, contains('4K'), reason: 'the 4K copy sorts above the HD one');
    expect(subtitles.last, contains('1080p'));
  });

  testWidgets('a re-resolve that comes back short keeps the copies already found', (tester) async {
    // The cross-server fan-out logs and skips per-server failures, so a later
    // pass can answer without a server that replied to the first one. Those
    // rows are still valid and must not be wiped.
    late _ScriptedMatcher matcher;
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: _enrichedRow));

    await _pumpDetail(
      tester,
      source,
      item: _bareRow,
      matcherBuilder: (multiServer) => matcher = _ScriptedMatcher(multiServer, [
        () => libraryLookupResult([_libraryCopy(id: 'hd-copy', libraryTitle: 'Movies')]),
        () => libraryLookupResult(const []),
      ]),
    );

    expect(matcher.calls, 2);
    expect(find.text(t.explore.inTheseLibraries), findsOneWidget);
    expect(_copyRow('Movies'), findsOneWidget);
    expect(find.text(t.explore.notInLibrary), findsNothing);
  });

  testWidgets('a failed re-resolve does not claim the title left the library', (tester) async {
    late _ScriptedMatcher matcher;
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: _enrichedRow));

    await _pumpDetail(
      tester,
      source,
      item: _bareRow,
      matcherBuilder: (multiServer) => matcher = _ScriptedMatcher(multiServer, [
        () => libraryLookupResult([_libraryCopy(id: 'hd-copy', libraryTitle: 'Movies')]),
        () => throw StateError('server unreachable'),
      ]),
    );

    expect(matcher.calls, 2);
    expect(_copyRow('Movies'), findsOneWidget);
    expect(find.text(t.explore.notInLibrary), findsNothing);
  });

  testWidgets('a server that could not be asked is reported instead of counted as a miss', (tester) async {
    // #2098: a slow or unreachable server is no evidence of absence. With no
    // copies found elsewhere, "Not in your library" would be a false claim.
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: _enrichedRow));

    await _pumpDetail(
      tester,
      source,
      item: _bareRow,
      matcherBuilder: (multiServer) => _ScriptedMatcher(multiServer, [
        () => libraryLookupResult(const [], failed: {'server-1'}),
      ]),
    );

    expect(find.text(t.explore.notInLibrary), findsNothing);
    expect(find.text(t.explore.libraryCheckFailed(n: 1)), findsOneWidget);
  });

  testWidgets('a server that was never asked is reported instead of counted as a miss', (tester) async {
    // An offline server is not in the fan-out at all, so it lands in no
    // failed or cancelled set — but "Not in your library" is still a false
    // claim about a server that never answered.
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: _enrichedRow));

    await _pumpDetail(
      tester,
      source,
      item: _bareRow,
      matcherBuilder: (multiServer) => _ScriptedMatcher(multiServer, [
        () => libraryLookupResult(const [], unqueried: {'server-1'}),
      ]),
    );

    expect(find.text(t.explore.notInLibrary), findsNothing);
    expect(find.text(t.explore.libraryCheckFailed(n: 1)), findsOneWidget);
  });

  testWidgets('an unchecked server is noted under the copies other servers found', (tester) async {
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: _enrichedRow));

    await _pumpDetail(
      tester,
      source,
      item: _bareRow,
      matcherBuilder: (multiServer) => _ScriptedMatcher(multiServer, [
        () => libraryLookupResult(
          [_libraryCopy(id: 'hd-copy', libraryTitle: 'Movies')],
          succeeded: {'server-1'},
          failed: {'server-2', 'server-3'},
        ),
      ]),
    );

    expect(find.text(t.explore.inTheseLibraries), findsOneWidget);
    expect(_copyRow('Movies'), findsOneWidget);
    expect(find.text(t.explore.libraryCheckFailed(n: 2)), findsOneWidget);
  });

  testWidgets('a server that answers a later pass stops being reported as unchecked', (tester) async {
    // A richer query's success replaces uncertainty from the bare-row query.
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: _enrichedRow));

    await _pumpDetail(
      tester,
      source,
      item: _bareRow,
      matcherBuilder: (multiServer) => _ScriptedMatcher(multiServer, [
        () => libraryLookupResult(const [], failed: {'server-1'}),
        () => libraryLookupResult(const [], succeeded: {'server-1'}),
      ]),
    );

    expect(find.text(t.explore.libraryCheckFailed(n: 1)), findsNothing);
    expect(find.text(t.explore.notInLibrary), findsOneWidget);
  });

  for (final nativeTitle in [false, true]) {
    for (final richerFinishesFirst in [false, true]) {
      testWidgets('${nativeTitle ? 'native-title' : 'external-id'} enrichment failure stays unchecked '
          'when ${richerFinishesFirst ? 'richer' : 'weaker'} lookup finishes first', (tester) async {
        final bare = nativeTitle ? _item : _bareRow;
        final enriched = nativeTitle
            ? const CatalogItem(
                source: CatalogSourceId.trakt,
                kind: MediaKind.movie,
                title: 'Catalog Movie',
                originalTitle: '銀河鉄道の夜',
                ids: CatalogItemIds(tmdb: 1),
              )
            : _enrichedRow;
        final detail = Completer<CatalogDetail>();
        final weaker = Completer<LibraryLookupResult>();
        final richer = Completer<LibraryLookupResult>();
        final source = _FakeCatalogSource(detailCompleter: detail);
        final copy = _libraryCopy(id: 'verified', libraryTitle: 'Verified Movies');

        await _pumpDetail(
          tester,
          source,
          item: bare,
          settle: false,
          matcherBuilder: (multiServer) => _ScriptedMatcher(multiServer, [() => weaker.future, () => richer.future]),
        );
        if (!richerFinishesFirst) {
          weaker.complete(libraryLookupResult([copy], succeeded: {'server-1'}));
          await tester.pumpAndSettle();
          expect(_copyRow('Verified Movies'), findsOneWidget);
        }
        detail.complete(CatalogDetail(item: enriched));
        await tester.pump();
        richer.complete(
          nativeTitle
              ? libraryLookupResult(const [], cancelled: {'server-1'})
              : libraryLookupResult(const [], failed: {'server-1'}),
        );
        await tester.pumpAndSettle();
        expect(find.text(t.explore.libraryCheckFailed(n: 1)), findsOneWidget);
        expect(find.text(t.explore.notInLibrary), findsNothing);

        if (richerFinishesFirst) {
          weaker.complete(libraryLookupResult([copy], succeeded: {'server-1'}));
          await tester.pumpAndSettle();
        }
        expect(_copyRow('Verified Movies'), findsOneWidget);
        expect(find.text(t.explore.libraryCheckFailed(n: 1)), findsOneWidget);
      });
    }
  }

  testWidgets('a weaker successful miss cannot turn failed enrichment into library absence', (tester) async {
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: _enrichedRow));
    await _pumpDetail(
      tester,
      source,
      item: _bareRow,
      matcherBuilder: (multiServer) => _ScriptedMatcher(multiServer, [
        () => libraryLookupResult(const [], succeeded: {'server-1'}),
        () => libraryLookupResult(const [], failed: {'server-1'}),
      ]),
    );

    expect(find.text(t.explore.notInLibrary), findsNothing);
    expect(find.text(t.explore.libraryCheckFailed(n: 1)), findsOneWidget);
  });

  testWidgets('a late weaker failure cannot overwrite richer successful-empty coverage', (tester) async {
    final weaker = Completer<LibraryLookupResult>();
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: _enrichedRow));
    await _pumpDetail(
      tester,
      source,
      item: _bareRow,
      matcherBuilder: (multiServer) => _ScriptedMatcher(multiServer, [
        () => weaker.future,
        () => libraryLookupResult(const [], succeeded: {'server-1'}),
      ]),
    );
    expect(find.text(t.explore.notInLibrary), findsOneWidget);

    weaker.complete(libraryLookupResult(const [], failed: {'server-1'}));
    await tester.pumpAndSettle();
    expect(find.text(t.explore.notInLibrary), findsOneWidget);
    expect(find.text(t.explore.libraryCheckFailed(n: 1)), findsNothing);
  });

  testWidgets('a re-resolve that lost its library stamp keeps the one already shown', (tester) async {
    // Jellyfin stamps a copy's library with a best-effort ancestors lookup
    // that returns the item bare when it fails. A row that fell back to the
    // server name would be indistinguishable from its sibling in the same
    // server's other library.
    late _ScriptedMatcher matcher;
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: _enrichedRow));

    await _pumpDetail(
      tester,
      source,
      item: _bareRow,
      matcherBuilder: (multiServer) => matcher = _ScriptedMatcher(multiServer, [
        () => libraryLookupResult([_libraryCopy(id: 'hd-copy', libraryTitle: 'Movies', videoResolution: '1080')]),
        () => libraryLookupResult([_libraryCopy(id: 'hd-copy', serverName: null)]),
      ]),
    );

    expect(matcher.calls, 2);
    expect(_copyRow('Movies'), findsOneWidget);
    final subtitles = tester.widgetList<Text>(find.textContaining('Living Room')).map((text) => text.data!);
    expect(subtitles.single, contains('1080p'), reason: 'the quality hint survives an unstamped re-resolve too');
  });

  testWidgets('a re-resolve that finds another library adds it to the list', (tester) async {
    // The exact `plex://` guid only sees libraries on the modern agent; a
    // legacy-agent sibling arrives with the enriched imdb/tmdb pass (#1754).
    // The first pass being non-empty must not suppress the second.
    late _ScriptedMatcher matcher;
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: _enrichedRow));

    await _pumpDetail(
      tester,
      source,
      item: _bareRow,
      matcherBuilder: (multiServer) => matcher = _ScriptedMatcher(multiServer, [
        () => libraryLookupResult([_libraryCopy(id: 'uhd-copy', libraryTitle: '4K Movies', videoResolution: '4k')]),
        () => libraryLookupResult([
          _libraryCopy(id: 'uhd-copy', libraryTitle: '4K Movies', videoResolution: '4k'),
          _libraryCopy(id: 'hd-copy', libraryTitle: 'Movies', videoResolution: '1080'),
        ]),
      ]),
    );

    expect(matcher.calls, 2);
    expect(_copyRow('4K Movies'), findsOneWidget, reason: 'the copy both passes agree on is not doubled');
    expect(_copyRow('Movies'), findsOneWidget);
  });

  testWidgets('focus stays on a library copy when a later pass adds one above it', (tester) async {
    // Merging re-sorts, so the rows can move. Focus nodes are keyed by the
    // copy, not by row index, or a dpad user would be thrown to another copy.
    final detailCompleter = Completer<CatalogDetail>();
    final source = _FakeCatalogSource(detailCompleter: detailCompleter);

    await _pumpDetail(
      tester,
      source,
      item: _bareRow,
      matcherBuilder: (multiServer) => _ScriptedMatcher(multiServer, [
        () => libraryLookupResult([_libraryCopy(id: 'hd-copy', libraryTitle: 'Movies', videoResolution: '1080')]),
        () => libraryLookupResult([
          _libraryCopy(id: 'hd-copy', libraryTitle: 'Movies', videoResolution: '1080'),
          _libraryCopy(id: 'uhd-copy', libraryTitle: '4K Movies', videoResolution: '4k'),
        ]),
      ]),
    );

    final tile = tester.widget<FocusableListTile>(
      find.ancestor(of: _copyRow('Movies'), matching: find.byType(FocusableListTile)),
    );
    tile.focusNode!.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_library_match_server-1:hd-copy');

    detailCompleter.complete(const CatalogDetail(item: _enrichedRow));
    await tester.pumpAndSettle();

    expect(_copyRow('4K Movies'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'catalog_library_match_server-1:hd-copy',
      reason: 'the 4K copy sorted above the focused HD copy without stealing focus',
    );
  });

  testWidgets('fetchDetail failure leaves the opening item rendered', (tester) async {
    final source = _FakeCatalogSource(detailError: StateError('detail unavailable'));

    await _pumpDetail(tester, source);

    expect(source.fetchDetailCalls, 1);
    expect(find.text('Catalog Movie'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text(t.explore.cast), findsNothing);
    expect(find.text(t.discover.moreLikeThis), findsNothing);
  });

  testWidgets('spoiler tags stay hidden until the focusable reveal action is pressed', (tester) async {
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Tagged Movie',
      ids: CatalogItemIds(tmdb: 10),
      tags: [
        CatalogTag(name: 'Found family', rank: 80),
        CatalogTag(name: 'Secret identity', rank: 95, isSpoiler: true),
      ],
    );
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: item));

    await _pumpDetail(tester, source, item: item);

    expect(find.text('Found family'), findsOneWidget);
    expect(find.text('Secret identity'), findsNothing);
    expect(find.text(t.explore.detail.revealSpoilerTags), findsOneWidget);

    await tester.tap(find.text(t.explore.detail.revealSpoilerTags));
    await tester.pump();

    expect(find.text('Secret identity'), findsOneWidget);
    expect(find.text(t.explore.detail.revealSpoilerTags), findsNothing);
  });

  testWidgets('ratings row labels every score source without a brand mark', (tester) async {
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Rated Movie',
      ids: CatalogItemIds(tmdb: 11),
      ratings: [
        MediaRatingSource(source: 'simkl', value: 8.1, votes: 11),
        MediaRatingSource(source: 'mal', value: 8.3, votes: 13),
        MediaRatingSource(source: 'critic', value: 7.2, votes: 14),
        MediaRatingSource(source: 'audience', value: 8.8, votes: 15),
      ],
    );
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: item));

    await _pumpDetail(tester, source, item: item);

    expect(find.text(t.explore.detail.ratings), findsOneWidget);
    expect(find.text('Simkl 8.1 (11 votes)'), findsOneWidget);
    expect(find.text('MyAnimeList 8.3 (13 votes)'), findsOneWidget);
    expect(find.text('Critics 7.2 (14 votes)'), findsOneWidget);
    expect(find.text('Audience 8.8 (15 votes)'), findsOneWidget);
  });

  testWidgets('averaging moves one score up to the poster chips and drops the ratings section', (tester) async {
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.show,
      title: 'Averaged Show',
      ids: CatalogItemIds(tmdb: 24),
      rating: 8.5,
      votes: 3616,
      ratings: [
        MediaRatingSource(source: 'simkl', value: 8.1, votes: 11),
        MediaRatingSource(source: 'mal', value: 8.3, votes: 13),
        MediaRatingSource(source: 'critic', value: 7.2, votes: 14),
        MediaRatingSource(source: 'audience', value: 8.8, votes: 15),
      ],
    );
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: item));

    await SettingsService.instance.write(SettingsService.averageRatings, true);
    await _pumpDetail(tester, source, item: item);

    // (8.1 + 8.3 + 7.2 + 8.8) / 4 = 8.1
    expect(find.text('${t.common.ratingSource.average} 8.1'), findsOneWidget);
    // The headline score it replaced is gone, and so is the whole section.
    expect(find.text('8.5 (3.62K votes)'), findsNothing);
    expect(find.text(t.explore.detail.ratings), findsNothing);
    expect(find.text('Simkl 8.1 (11 votes)'), findsNothing);
    expect(find.text('Audience 8.8 (15 votes)'), findsNothing);
  });

  testWidgets('the poster chips follow the averaging switch without reopening the page', (tester) async {
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.show,
      title: 'Live Toggle Show',
      ids: CatalogItemIds(tmdb: 25),
      rating: 8.5,
      votes: 3616,
      ratings: [
        MediaRatingSource(source: 'simkl', value: 8.0, votes: 11),
        MediaRatingSource(source: 'mal', value: 9.0, votes: 13),
      ],
    );
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: item));

    await _pumpDetail(tester, source, item: item);
    expect(find.text('8.5 (3.62K votes)'), findsOneWidget);
    expect(find.text(t.explore.detail.ratings), findsOneWidget);

    await SettingsService.instance.write(SettingsService.averageRatings, true);
    await tester.pumpAndSettle();

    expect(find.text('${t.common.ratingSource.average} 8.5'), findsOneWidget);
    expect(find.text('8.5 (3.62K votes)'), findsNothing);
    expect(find.text(t.explore.detail.ratings), findsNothing);
  });

  testWidgets('a lone attributed score keeps its own section rather than posing as an average', (tester) async {
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Single Score Movie',
      ids: CatalogItemIds(tmdb: 26),
      rating: 8.5,
      votes: 3616,
      ratings: [MediaRatingSource(source: 'simkl', value: 8.1, votes: 11)],
    );
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: item));

    await SettingsService.instance.write(SettingsService.averageRatings, true);
    await _pumpDetail(tester, source, item: item);

    expect(find.textContaining(t.common.ratingSource.average), findsNothing);
    expect(find.text('8.5 (3.62K votes)'), findsOneWidget);
    expect(find.text('Simkl 8.1 (11 votes)'), findsOneWidget);
  });

  testWidgets('scores whose source owns a logo render the mark and that source scale', (tester) async {
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Attributed Movie',
      ids: CatalogItemIds(tmdb: 21),
      ratings: [
        MediaRatingSource(source: 'rottenTomatoesCritic', value: 8.4),
        MediaRatingSource(source: 'rottenTomatoesAudience', value: 4.1),
        MediaRatingSource(source: 'imdb', value: 7.9, votes: 12),
        MediaRatingSource(source: 'tmdb', value: 7.5),
      ],
    );
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: item));

    await _pumpDetail(tester, source, item: item);

    expect(
      tester
          .widgetList<SvgPicture>(find.byType(SvgPicture))
          .map((picture) => picture.bytesLoader)
          .whereType<SvgAssetLoader>()
          .map((loader) => loader.assetName),
      containsAll(const [
        'assets/rating_icons/rt_fresh.svg',
        'assets/rating_icons/rt_spilled.svg',
        'assets/rating_icons/imdb.svg',
        'assets/rating_icons/tmdb.svg',
      ]),
    );
    // The mark carries the attribution, so the chip keeps only the score, on
    // the scale that source publishes.
    expect(find.text('84%'), findsOneWidget);
    expect(find.text('41%'), findsOneWidget);
    expect(find.text('7.9 (12 votes)'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('${t.common.ratingSource.rottenTomatoesCritic} 8.4'), findsNothing);
  });

  testWidgets('seasonal rank keeps its season window instead of claiming all-time rank', (tester) async {
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.show,
      title: 'Seasonal Show',
      ids: CatalogItemIds(tmdb: 12),
      ranks: [
        CatalogRank(
          rank: 7,
          scope: CatalogRankScope.popular,
          allTime: false,
          year: 2025,
          season: CatalogSeasonName.fall,
        ),
      ],
    );
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: item));

    await _pumpDetail(tester, source, item: item);

    expect(find.text('#7 in Fall 2025'), findsOneWidget);
    expect(find.text('#7 popular'), findsNothing);
  });

  testWidgets('windowed viewers render only when their period is present', (tester) async {
    const missingPeriod = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Missing Period',
      ids: CatalogItemIds(tmdb: 13),
      audience: CatalogAudience(listed: 3, viewers: 42),
    );
    final firstSource = _FakeCatalogSource(detail: const CatalogDetail(item: missingPeriod));
    await _pumpDetail(tester, firstSource, item: missingPeriod);

    expect(find.text('3 listed'), findsOneWidget);
    expect(find.textContaining('42'), findsNothing);

    const weekly = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Weekly Viewers',
      ids: CatalogItemIds(tmdb: 14),
      audience: CatalogAudience(viewers: 42, viewersPeriod: CatalogAudiencePeriod.week),
    );
    // Unmount first: pumping a second detail screen at the same tree position
    // would reuse the existing State, so `initState` would never re-run and
    // the screen would keep the previous item.
    await tester.pumpWidget(const SizedBox.shrink());
    final secondSource = _FakeCatalogSource(detail: const CatalogDetail(item: weekly));
    await _pumpDetail(tester, secondSource, item: weekly);

    expect(find.text('42 watched this week'), findsOneWidget);
  });

  testWidgets('trailer action appears only after an item supplies a trailer URL', (tester) async {
    final detailCompleter = Completer<CatalogDetail>();
    final source = _FakeCatalogSource(detailCompleter: detailCompleter);

    await _pumpDetail(tester, source);
    expect(find.byTooltip(t.explore.detail.watchTrailer), findsNothing);

    detailCompleter.complete(
      const CatalogDetail(
        item: CatalogItem(
          source: CatalogSourceId.trakt,
          kind: MediaKind.movie,
          title: 'Catalog Movie',
          trailerUrl: 'https://example.com/trailer',
          ids: CatalogItemIds(tmdb: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip(t.explore.detail.watchTrailer), findsOneWidget);
  });

  testWidgets('background prose renders as its own section', (tester) async {
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Production Movie',
      ids: CatalogItemIds(tmdb: 15),
      background: 'Filmed over three winters.',
    );
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: item));

    await _pumpDetail(tester, source, item: item);

    expect(find.text(t.explore.detail.background), findsOneWidget);
    expect(find.text('Filmed over three winters.'), findsOneWidget);
  });

  testWidgets('budget and box office pair into columns on a wide window and stack on a narrow one', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Expensive Movie',
      ids: CatalogItemIds(tmdb: 22),
      budget: 165000000,
      revenue: 675000000,
    );
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: item));

    await _pumpDetail(tester, source, item: item);

    final budget = find.text(t.explore.detail.budget);
    final revenue = find.text(t.explore.detail.revenue);
    expect(tester.getTopLeft(revenue).dy, tester.getTopLeft(budget).dy);
    expect(tester.getTopLeft(revenue).dx, greaterThan(tester.getTopLeft(budget).dx));

    tester.view.physicalSize = const Size(420, 900);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(revenue).dy, greaterThan(tester.getTopLeft(budget).dy));
    expect(tester.getTopLeft(revenue).dx, tester.getTopLeft(budget).dx);
  });

  testWidgets('all-null metadata renders without an empty optional section header', (tester) async {
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Bare Movie',
      ids: CatalogItemIds(tmdb: 15),
    );
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: item));

    await _pumpDetail(tester, source, item: item);

    expect(find.text('Bare Movie'), findsOneWidget);
    expect(find.text(t.explore.detail.ratings), findsNothing);
    expect(find.text(t.explore.detail.schedule), findsNothing);
    expect(find.text(t.explore.detail.crew), findsNothing);
    expect(find.text(t.explore.detail.tags), findsNothing);
    expect(find.text(t.explore.detail.links), findsNothing);
    expect(find.text(t.explore.detail.watchOn), findsNothing);
    expect(find.text(t.explore.cast), findsNothing);
    expect(find.text(t.discover.moreLikeThis), findsNothing);
    expect(find.text(t.explore.detail.relatedTitles), findsNothing);
    expect(find.text(t.explore.detail.background), findsNothing);
  });

  testWidgets('single-entry relations share one labelled section instead of a shelf each', (tester) async {
    const sequel = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'The Sequel',
      year: 2019,
      posterUrl: 'https://example.com/sequel.jpg',
      ids: CatalogItemIds(tmdb: 17),
    );
    const spinOff = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'The Spin-off',
      ids: CatalogItemIds(tmdb: 20),
    );
    const recommendation = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'A Similar Movie',
      ids: CatalogItemIds(tmdb: 18),
    );
    final source = _FakeCatalogSource(
      detail: const CatalogDetail(
        item: _item,
        related: [recommendation],
        relations: [
          CatalogRelation(type: CatalogRelationType.sequel, items: [sequel]),
          CatalogRelation(type: CatalogRelationType.spinOff, items: [spinOff]),
        ],
      ),
    );

    await _pumpDetail(tester, source);

    // Recommendations keep their shelf; two one-title relations do not get one
    // each.
    expect(find.byType(HubSection), findsOneWidget);
    expect(find.text(t.discover.moreLikeThis), findsOneWidget);
    expect(find.text('A Similar Movie'), findsOneWidget);

    expect(find.text(t.explore.detail.relatedTitles), findsOneWidget);
    expect(find.text(t.explore.relation.sequel), findsOneWidget);
    expect(find.text(t.explore.relation.spinOff), findsOneWidget);
    expect(find.text('The Sequel • 2019'), findsOneWidget);
    expect(find.text('The Spin-off'), findsOneWidget);
    expect(
      tester.widgetList<OptimizedMediaImage>(find.byType(OptimizedMediaImage)).map((image) => image.imagePath),
      contains('https://example.com/sequel.jpg'),
    );
  });

  testWidgets('a relation row opens the catalog detail screen of that title', (tester) async {
    const sequel = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'The Sequel',
      ids: CatalogItemIds(tmdb: 17),
    );
    final source = _FakeCatalogSource(
      detail: const CatalogDetail(
        item: _item,
        relations: [
          CatalogRelation(type: CatalogRelationType.sequel, items: [sequel]),
        ],
      ),
    );

    await _pumpDetail(tester, source);
    await tester.tap(find.text('The Sequel'));
    await tester.pumpAndSettle();

    expect(find.byType(CatalogItemDetailScreen, skipOffstage: false), findsNWidgets(2));
    expect(find.text('The Sequel'), findsOneWidget);
  });

  testWidgets('D-pad walks the relation rows between the cast strip and recommendations', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const prequel = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'The Prequel',
      ids: CatalogItemIds(tmdb: 16),
    );
    const sequel = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'The Sequel',
      ids: CatalogItemIds(tmdb: 17),
    );
    final source = _FakeCatalogSource(
      detail: const CatalogDetail(
        item: _item,
        cast: [CatalogCastMember(name: 'First Actor', secondary: 'Lead')],
        related: [
          CatalogItem(
            source: CatalogSourceId.trakt,
            kind: MediaKind.movie,
            title: 'Related Movie',
            ids: CatalogItemIds(tmdb: 2),
          ),
        ],
        relations: [
          CatalogRelation(type: CatalogRelationType.prequel, items: [prequel]),
          CatalogRelation(type: CatalogRelationType.sequel, items: [sequel]),
        ],
      ),
    );

    await _pumpDetail(tester, source);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_overview');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_cast_row');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_relation_0');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_relation_1');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, startsWith('hub_catalog-related:'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_relation_1');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_cast_row');
  });

  testWidgets('social recommendation keeps its person, reason, and note', (tester) async {
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Social Movie',
      ids: CatalogItemIds(tmdb: 19),
      recommenders: [
        CatalogRecommender(
          username: 'pat',
          name: 'Pat',
          note: 'A thoughtful recommendation.',
          reason: CatalogRecommendationReason.recommended,
        ),
      ],
    );
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: item));

    await _pumpDetail(tester, source, item: item);

    expect(find.text('Recommended by Pat'), findsOneWidget);
    expect(find.text('A thoughtful recommendation.'), findsOneWidget);
  });

  testWidgets('extended facts render in their labelled sections with localized values', (tester) async {
    final item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.show,
      title: 'Fact-rich Show',
      ids: CatalogItemIds(tmdb: 20),
      broadcastSeason: CatalogSeasonInfo(name: CatalogSeasonName.fall, year: 2025),
      format: CatalogFormat.ova,
      sourceMaterial: CatalogSourceMaterial.lightNovel,
      studios: ['Studio One'],
      countries: ['US'],
      languages: ['ja'],
      credits: [
        CatalogCredit(name: 'A. Director', role: CatalogCreditRole.director),
        CatalogCredit(name: 'W. Writer', role: CatalogCreditRole.writer),
      ],
      broadcast: CatalogBroadcast(weekday: DateTime.tuesday, time: '21:00', timezone: 'Asia/Tokyo'),
      nextEpisode: CatalogNextEpisode(episode: 4, airsAt: DateTime.utc(2100)),
      serverState: CatalogServerState(
        availability: CatalogAvailability.available,
        request: CatalogRequestState.pending,
        availableSeasons: 2,
        totalSeasons: 3,
      ),
      audience: CatalogAudience(dropRate: 0.25),
      releaseDate: DateTime.utc(2024, 1, 2),
      physicalReleaseDate: DateTime.utc(2024, 4, 5),
      endDate: DateTime.utc(2025, 6, 7),
      addedAt: DateTime.utc(2024, 2, 3),
      userRating: 9,
      originalTitle: 'Original Fact Title',
      altTitles: ['Alternate Fact Title'],
      contentAdvisory: 'Suitable for older teens.',
      budget: 1000000,
      revenue: 2500000,
      links: [
        CatalogLink(label: 'StreamCo', url: 'https://example.com/watch', isStreaming: true),
        CatalogLink(label: 'Official Site', url: 'https://example.com'),
      ],
    );
    final source = _FakeCatalogSource(detail: CatalogDetail(item: item));

    await _pumpDetail(tester, source, item: item);

    expect(find.text('Fall 2025'), findsOneWidget);
    expect(find.text('OVA'), findsOneWidget);
    expect(find.text('Light novel'), findsOneWidget);
    expect(find.text('25% dropped it'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Pending approval'), findsOneWidget);
    expect(find.text('2/3 seasons'), findsOneWidget);
    expect(find.text('Airs Tuesday at 21:00 Asia/Tokyo'), findsOneWidget);
    expect(find.textContaining('Ep 4 in'), findsOneWidget);
    expect(find.text('United States'), findsOneWidget);
    expect(find.text('Japanese'), findsOneWidget);
    expect(find.text(t.explore.detail.crew), findsOneWidget);
    expect(find.text('A. Director'), findsOneWidget);
    expect(find.text('W. Writer'), findsOneWidget);
    expect(find.text(t.explore.detail.watchOn), findsOneWidget);
    expect(find.text('Open on StreamCo'), findsOneWidget);
    // Non-streaming provider links are not shown at all any more.
    expect(find.text(t.explore.detail.links), findsNothing);
    expect(find.text('Open on Official Site'), findsNothing);
    expect(find.text('Original Fact Title'), findsOneWidget);
    expect(find.text('Alternate Fact Title'), findsOneWidget);
    expect(find.text('Suitable for older teens.'), findsOneWidget);
    expect(find.textContaining('1,000,000'), findsOneWidget);
    expect(find.textContaining('2,500,000'), findsOneWidget);
  });

  testWidgets('the detail-facts setting hides the fact grid and keeps the rest of the page', (tester) async {
    final item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Fact Toggle Movie',
      overview: 'Overview stays visible',
      ids: CatalogItemIds(tmdb: 22),
      originalTitle: 'Original Fact Title',
      altTitles: ['Alternate Fact Title'],
      countries: ['US'],
      credits: [CatalogCredit(name: 'A. Director', role: CatalogCreditRole.director)],
    );
    final source = _FakeCatalogSource(detail: CatalogDetail(item: item));

    await SettingsService.instance.write(SettingsService.showCatalogDetailFacts, false);
    await _pumpDetail(tester, source, item: item);

    expect(find.text('Original Fact Title'), findsNothing);
    expect(find.text('Alternate Fact Title'), findsNothing);
    expect(find.text(t.explore.detail.alsoKnownAs), findsNothing);
    // Only the fact grid goes; the synopsis and the crew block are separate
    // sections and must survive.
    expect(find.text('Overview stays visible'), findsOneWidget);
    expect(find.text('A. Director'), findsOneWidget);

    // The page reacts to the switch without being reopened.
    await SettingsService.instance.write(SettingsService.showCatalogDetailFacts, true);
    await tester.pumpAndSettle();

    expect(find.text('Original Fact Title'), findsOneWidget);
    expect(find.text('Alternate Fact Title'), findsOneWidget);
  });

  testWidgets('the crew setting hides only the crew grid', (tester) async {
    final item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.show,
      title: 'Crew Toggle Show',
      overview: 'Overview stays visible',
      ids: CatalogItemIds(tmdb: 27),
      originalTitle: 'Original Fact Title',
      credits: [
        CatalogCredit(name: 'A. Director', role: CatalogCreditRole.director),
        CatalogCredit(name: 'W. Writer', role: CatalogCreditRole.writer),
      ],
    );
    final source = _FakeCatalogSource(detail: CatalogDetail(item: item));

    await SettingsService.instance.write(SettingsService.showCatalogDetailCrew, false);
    await _pumpDetail(tester, source, item: item);

    expect(find.text(t.explore.detail.crew), findsNothing);
    expect(find.text('A. Director'), findsNothing);
    expect(find.text('W. Writer'), findsNothing);
    // The neighbouring sections stay put.
    expect(find.text('Overview stays visible'), findsOneWidget);
    expect(find.text('Original Fact Title'), findsOneWidget);

    await SettingsService.instance.write(SettingsService.showCatalogDetailCrew, true);
    await tester.pumpAndSettle();

    expect(find.text(t.explore.detail.crew), findsOneWidget);
    expect(find.text('A. Director'), findsOneWidget);
  });

  testWidgets('detail facts are shown by default', (tester) async {
    final item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Default Facts Movie',
      ids: CatalogItemIds(tmdb: 23),
      originalTitle: 'Original Fact Title',
    );
    final source = _FakeCatalogSource(detail: CatalogDetail(item: item));

    await _pumpDetail(tester, source, item: item);

    expect(SettingsService.instance.read(SettingsService.showCatalogDetailFacts), isTrue);
    expect(find.text('Original Fact Title'), findsOneWidget);
  });

  testWidgets('D-pad includes spoiler reveal and outbound links after the main action bar', (tester) async {
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Interactive Movie',
      ids: CatalogItemIds(tmdb: 21),
      trailerUrl: 'https://example.com/trailer',
      tags: [CatalogTag(name: 'Spoiler', isSpoiler: true)],
      links: [
        CatalogLink(label: 'StreamCo', url: 'https://example.com/watch', isStreaming: true),
        CatalogLink(label: 'OtherStream', url: 'https://example.com/watch-2', isStreaming: true),
      ],
    );
    final source = _FakeCatalogSource(detail: const CatalogDetail(item: item));

    await _pumpDetail(tester, source, item: item);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_watchlist');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_spoiler_tags');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_external_link_0');

    // Links inside one section sit side by side, so the walk between them is
    // horizontal; DOWN leaves the group entirely.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_external_link_1');
  });

  testWidgets('D-pad traverses from actions through cast and back from recommendations', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpDetail(tester, _FakeCatalogSource());
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_watchlist');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_overview');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_cast_row');
    expect(
      tester.widget<SingleChildScrollView>(find.byKey(const Key('catalog_detail_scroll'))).controller!.offset,
      greaterThan(0),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, startsWith('hub_catalog-related:'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_cast_row');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_overview');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_watchlist');
    expect(tester.widget<SingleChildScrollView>(find.byKey(const Key('catalog_detail_scroll'))).controller!.offset, 0);
  });

  testWidgets('D-pad includes every library match between actions and cast', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    // Copies render best-first, so the 4K one leads whatever order the
    // matcher returned them in.
    final matches = [
      testMediaItem(
        id: 'match_1',
        libraryTitle: 'Movies',
        serverName: 'Living Room',
        mediaVersions: const [MediaVersion(id: 'v1', videoResolution: '4k')],
      ),
      testMediaItem(
        id: 'match_2',
        libraryTitle: 'Favorites',
        serverName: 'Bedroom',
        mediaVersions: const [MediaVersion(id: 'v2', videoResolution: '1080')],
      ),
    ];
    await _pumpDetail(tester, _FakeCatalogSource(), matches: matches);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_overview');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_library_match_match_1');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_library_match_match_2');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_cast_row');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_library_match_match_2');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_library_match_match_1');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_overview');
  });

  testWidgets('D-pad stops on the overview and expands it before moving on to the buttons', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    // #2199: down from the action bar used to be thrown straight to the next
    // button, scrolling long prose past unread.
    final item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Wordy Movie',
      overview: '${'A very long establishing sentence about the movie. ' * 30}Closing line of the overview.',
      ids: const CatalogItemIds(tmdb: 31),
      links: const [CatalogLink(label: 'StreamCo', url: 'https://example.com/watch', isStreaming: true)],
    );
    final source = _FakeCatalogSource(detail: CatalogDetail(item: item));

    await _pumpDetail(tester, source, item: item);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_watchlist');
    expect(find.textContaining('Closing line'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_overview');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.textContaining('Closing line'), findsOneWidget, reason: 'select expands the collapsed overview');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_overview');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_external_link_0');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_overview');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_watchlist');
  });

  testWidgets('up from the first library copy reaches the overview, then the best-copy button', (tester) async {
    // No watchlist support, trailer, or Seerr: the only button above the
    // copies is the one that opens the best of them, and the overview is
    // still a stop on the way up rather than skipped.
    final source = _FakeCatalogSource(supportsWatchlist: false);
    await _pumpDetail(
      tester,
      source,
      matches: [
        testMediaItem(
          id: 'match_1',
          libraryTitle: 'Movies',
          serverName: 'Living Room',
          mediaVersions: const [MediaVersion(id: 'v1', videoResolution: '4k')],
        ),
      ],
    );
    expect(find.byType(LibraryCopyJumpButton), findsOneWidget);

    final tile = tester.widget<FocusableListTile>(
      find.ancestor(of: _copyRow('Movies'), matching: find.byType(FocusableListTile)),
    );
    tile.focusNode!.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_overview');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_best_copy');
  });

  testWidgets('a press while the list is still loading is carried out, not dropped', (tester) async {
    final source = _FakeCatalogSource(watchlistLoading: true);
    await _pumpDetail(tester, source);

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_watchlist');
    final actionNode = tester
        .widgetList<Focus>(find.descendant(of: find.byType(FocusableActionBar), matching: find.byType(Focus)))
        .map((widget) => widget.focusNode)
        .whereType<FocusNode>()
        .singleWhere((node) => node.debugLabel == 'catalog_watchlist');
    expect(actionNode.canRequestFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(source.addToWatchlistCalls, 0, reason: 'nothing to toggle until membership is known');

    source.completeWatchlistLoad();
    await tester.pumpAndSettle();

    // The press waited for the list rather than being discarded: one press,
    // one add. Dropping it left the button doing nothing at all.
    expect(source.addToWatchlistCalls, 1);
  });

  testWidgets('a list that cannot be read does not block adding to it', (tester) async {
    // Plex Discover answers 504 for the watchlist often enough to be
    // ordinary. That is a failed read, and adding needs the item's own id
    // rather than the list — so the press goes through.
    final source = _FakeCatalogSource(watchlistUnreadable: true);
    await _pumpDetail(tester, source);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(source.addToWatchlistCalls, 1);
  });
  testWidgets('TV Back closes a hosted sheet without popping the catalog route', (tester) async {
    await _pumpDetail(tester, _FakeCatalogSource(), pushedRoute: true);

    final sheetResult = OverlaySheetController.showAdaptive<void>(
      tester.element(find.byType(FocusableActionBar)),
      builder: (_) => const SizedBox(height: 120, child: Center(child: Text('Hosted request sheet'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hosted request sheet'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.gameButtonB);
    // Android TV can dispatch route Back for the same remote press. Deliver
    // that duplicate in the same key sequence, before the coordinator's
    // one-frame ownership marker is cleared.
    await tester.binding.handlePopRoute();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();

    expect(find.text('Hosted request sheet'), findsNothing);
    expect(find.byType(CatalogItemDetailScreen), findsOneWidget);
    await expectLater(sheetResult, completion(isNull));

    // A later, independent system Back still pops the catalog route.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CatalogItemDetailScreen), findsNothing);
  });

  testWidgets('recommendation posters use compact grid-equivalent TV sizing', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpDetail(tester, _FakeCatalogSource());

    expect(tester.getSize(find.byType(MediaCard).first).width, lessThan(210));
  });
}

/// A library copy's row under "In these libraries" — not the best-copy
/// button above it, which names the same library.
Finder _copyRow(String library) => find.descendant(of: find.byType(LibraryCopyTile), matching: find.text(library));

/// A server that says what its copies hold, as Plex and Jellyfin both do: a
/// film by its own detail, a series by its first episode.
class _QualityServer implements MediaServerClient {
  _QualityServer(this.id, {this.items = const {}, this.leaves = const {}});

  final String id;
  final Map<String, MediaItem> items;
  final Map<String, List<MediaItem>> leaves;

  @override
  ServerId get serverId => ServerId(id);

  @override
  Future<MediaItem?> fetchItem(String itemId) async => items[itemId];

  @override
  void close() {}

  @override
  Future<LibraryPage<MediaItem>> fetchPlayableDescendantsPage(String parentId, {int? start, int? size, abort}) async =>
      fakeLibraryPage(leaves[parentId] ?? const <MediaItem>[], start: start, size: size);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaVersion _episodeVersion({required String resolution, bool dolbyVision = false}) => MediaVersion(
  id: 'v-$resolution',
  videoResolution: resolution,
  parts: [
    MediaPart(
      id: 'p',
      streams: [MediaStream(id: 'video', kind: MediaStreamKind.video, dolbyVision: dolbyVision)],
    ),
  ],
);

/// "Dark Matter" twice: all 19 episodes in HD on Jellyfin, season one in
/// 4K Dolby Vision on Plex.
({List<MediaItem> copies, List<MediaServerClient> servers}) _darkMatter() {
  final hd = testMediaItem(
    id: 'jf-show',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.show,
    libraryTitle: 'HD Serien',
    serverId: 'jellyfin',
    serverName: 'VNext Jellyfin',
    leafCount: 19,
  );
  final uhd = testMediaItem(
    id: 'plex-show',
    kind: MediaKind.show,
    libraryTitle: '4K Serien',
    serverId: 'plex',
    serverName: 'Plex',
    leafCount: 8,
  );
  return (
    copies: [hd, uhd],
    servers: [
      _QualityServer(
        'jellyfin',
        leaves: {
          'jf-show': [testMediaItem(id: 'jf-e1', kind: MediaKind.episode)],
        },
        items: {
          'jf-e1': testMediaItem(
            id: 'jf-e1',
            kind: MediaKind.episode,
            mediaVersions: [_episodeVersion(resolution: '1080')],
          ),
        },
      ),
      _QualityServer(
        'plex',
        leaves: {
          'plex-show': [testMediaItem(id: 'plex-e1', kind: MediaKind.episode)],
        },
        items: {
          'plex-e1': testMediaItem(
            id: 'plex-e1',
            kind: MediaKind.episode,
            mediaVersions: [_episodeVersion(resolution: '4k', dolbyVision: true)],
          ),
        },
      ),
    ],
  );
}

void _bestCopyTests() {
  testWidgets('the best copy is one button beside the poster, and the cursor starts on it', (tester) async {
    final darkMatter = _darkMatter();
    final opened = <MediaItem>[];
    await _pumpDetail(
      tester,
      _FakeCatalogSource(),
      matches: darkMatter.copies,
      clients: darkMatter.servers,
      onOpenLibraryCopy: opened.add,
    );

    final button = find.byType(LibraryCopyJumpButton);
    expect(button, findsOneWidget);
    expect(find.descendant(of: button, matching: find.text('4K Serien')), findsOneWidget);
    expect(find.descendant(of: button, matching: find.text('4K · DV')), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog_best_copy');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(opened.single.id, 'plex-show', reason: 'the copy on its own server, not the Explore entry');
  });

  testWidgets('quality before completeness, and the button says what is missing', (tester) async {
    final darkMatter = _darkMatter();
    await _pumpDetail(tester, _FakeCatalogSource(), matches: darkMatter.copies, clients: darkMatter.servers);

    expect(find.text(t.explore.episodesOf(have: 8, total: 19)), findsOneWidget);
    // The rows below follow the same order and now say what each copy holds.
    final rows = tester.widgetList<LibraryCopyTile>(find.byType(LibraryCopyTile)).toList();
    expect(rows.map((row) => row.copy.id), ['plex-show', 'jf-show']);
    expect(
      find.descendant(of: find.byType(LibraryCopyTile), matching: find.textContaining(t.explore.episodeCount(n: 19))),
      findsOneWidget,
    );
  });

  testWidgets('one copy needs no comparing: the button opens it straight away', (tester) async {
    final opened = <MediaItem>[];
    await _pumpDetail(
      tester,
      _FakeCatalogSource(),
      matches: [testMediaItem(id: 'only', libraryTitle: 'Movies', serverName: 'Living Room')],
      onOpenLibraryCopy: opened.add,
    );

    await tester.tap(find.byType(LibraryCopyJumpButton));
    await tester.pump();
    expect(opened.single.id, 'only');
  });

  testWidgets('copies no server could measure keep the lookup order', (tester) async {
    final opened = <MediaItem>[];
    // No clients registered: nothing can be measured.
    await _pumpDetail(
      tester,
      _FakeCatalogSource(),
      matches: [
        testMediaItem(
          id: 'hd',
          libraryTitle: 'Movies',
          mediaVersions: const [MediaVersion(id: 'v', videoResolution: '1080')],
        ),
        testMediaItem(
          id: 'uhd',
          libraryTitle: '4K Movies',
          mediaVersions: const [MediaVersion(id: 'v', videoResolution: '4k')],
        ),
      ],
      onOpenLibraryCopy: opened.add,
    );

    await tester.tap(find.byType(LibraryCopyJumpButton));
    await tester.pump();
    expect(opened.single.id, 'uhd');
  });

  testWidgets('a server that was not asked is named under the button', (tester) async {
    // The screenshot's case: Jellyfin answered, Plex did not. The button goes
    // to the best copy it knows of and says which server it could not ask.
    await _pumpDetail(
      tester,
      _FakeCatalogSource(detail: const CatalogDetail(item: _enrichedRow)),
      item: _bareRow,
      matcherBuilder: (multiServer) => _ScriptedMatcher(multiServer, [
        () => libraryLookupResult(
          [_libraryCopy(id: 'hd-copy', libraryTitle: 'Movies')],
          succeeded: {'server-1'},
          failed: {'plex-home'},
        ),
      ]),
    );

    expect(find.byType(LibraryCopyJumpButton), findsOneWidget);
    expect(find.text(t.explore.notChecked(servers: 'plex-home')), findsOneWidget);
  });

  testWidgets('without a copy there is no button', (tester) async {
    await _pumpDetail(tester, _FakeCatalogSource());
    expect(find.byType(LibraryCopyJumpButton), findsNothing);
  });
}
