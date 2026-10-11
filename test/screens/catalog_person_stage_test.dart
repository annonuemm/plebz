import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:http/testing.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_person.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/redesign/ocker_skin.dart' show debugOckerLayoutOnThisHost;
import 'package:plezy/screens/catalog_person_screen.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/catalog/plex_catalog_source.dart';
import 'package:plezy/services/plex_discover_client.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/media_card_sliver_layout.dart';
import 'package:provider/provider.dart';

import '../test_helpers/http_fixtures.dart';
import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/paged_fakes.dart';
import '../test_helpers/prefs.dart';

/// One Plex server that knows the person by name and holds "Drive".
class _PersonServer implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('srv');

  @override
  Future<List<MediaPerson>> searchPeople(
    String query, {
    int limit = 20,
    AbortController? abort,
    Set<String> excludedLibraryIds = const {},
  }) async => [MediaPerson(id: '7', name: query, backend: MediaBackend.plex, serverId: serverId)];

  @override
  Future<LibraryPage<MediaItem>> fetchPersonMediaPage(
    String personId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => fakeLibraryPage(
    [
      MediaItem.plex(
        id: '101',
        kind: MediaKind.movie,
        guid: 'plex://movie/drive',
        title: 'Drive',
        year: 2011,
        serverId: 'srv',
      ),
    ],
    start: start,
    size: size,
  );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sources extends CatalogSourcesProvider {
  _Sources(this.plex);

  final PlexCatalogSource plex;

  @override
  List<CatalogSource> get connectedSources => [plex];
}

Map<String, Object?> _credit(String key, String title, int year, {String type = 'movie', String? role}) => {
  'role': ?role,
  'Metadata': {'ratingKey': key, 'type': type, 'title': title, 'year': year},
};

PlexCatalogSource _discover({int extra = 0}) => PlexCatalogSource(
  PlexDiscoverClient(
    const PlexDiscoverSession(accessToken: 't', clientIdentifier: 'c'),
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/credits')) {
        return jsonResponse({
          'MediaContainer': {
            'CreditGroup': [
              {
                'type': 'actor',
                'Credit': [
                  _credit('drive', 'Drive', 2011, role: 'Shannon'),
                  _credit('argo', 'Argo', 2012, role: 'Jack'),
                  for (var i = 0; i < extra; i++) _credit('c$i', 'Film $i', 2000 - i, role: 'Role $i'),
                ],
              },
              {
                'type': 'appeared',
                'Credit': [_credit('snl', 'Saturday Night Live', 1975, type: 'show', role: 'Self')],
              },
            ],
          },
        });
      }
      return jsonResponse({
        'MediaContainer': {
          'Metadata': [
            {
              'title': 'Bryan Cranston',
              'summary': 'A long biography.',
              'bornAt': '1956-03-07',
              'birthPlace': 'Hollywood',
              'knownFor': 'Acting',
              'CreditType': [
                {'type': 'actor'},
                {'type': 'director'},
              ],
            },
          ],
        },
      });
    }),
  ),
);

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    AppThemeVariant variant = AppThemeVariant.glas,
    int extraCredits = 0,
    bool tall = true,
  }) async {
    // Tall enough that both grids are laid out, not scrolled away.
    tester.view.physicalSize = Size(1920, tall ? 3200 : 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final servers = testMultiServer(clients: [_PersonServer()]);
    final sources = _Sources(_discover(extra: extraCredits));
    addTearDown(sources.dispose);
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogSourcesProvider>.value(value: sources),
            ChangeNotifierProvider<MultiServerProvider>.value(value: servers.provider),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true, variant: variant),
            home: const CatalogPersonScreen(
              name: 'Bryan Cranston',
              personId: 'pid',
              characterName: 'Walter White',
              sourceTitle: 'Breaking Bad',
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('on a television under the redesign', () {
    setUp(() {
      TvDetectionService.debugSetAppleTVOverride(true);
      debugOckerLayoutOnThisHost = true;
    });
    tearDown(() {
      debugOckerLayoutOnThisHost = null;
      TvDetectionService.debugSetAppleTVOverride(null);
    });

    for (final variant in [AppThemeVariant.glas, AppThemeVariant.flach]) {
      testWidgets('${variant.name}: filters over the grids, and the remote between them', (tester) async {
        await pumpPage(tester, variant: variant);

        expect(find.text('Bryan Cranston'), findsWidgets);
        expect(find.text(t.actor.asRoleIn(role: 'Walter White', title: 'Breaking Bad')), findsWidgets);
        expect(find.text('${t.libraries.groupings.all}  3'), findsOneWidget);
        expect(find.text('${t.libraries.groupings.movies}  2'), findsOneWidget);
        expect(
          find.textContaining(t.libraries.groupings.shows),
          findsNothing,
          reason: 'a kind with no titles is hidden',
        );
        expect(find.text('${t.actor.availability.available}  1'), findsOneWidget);
        expect(find.text('${t.actor.availability.missing}  2'), findsOneWidget);
        // Both grids, each poster with its role.
        expect(find.text('Shannon'), findsOneWidget);
        expect(find.text('Jack'), findsOneWidget);
        expect(focused(), 'person_tab_all');
        // Six posters a row on the stage, whatever the library density.
        expect(
          tester
              .widgetList<MediaCardSliverLayout>(find.byType(MediaCardSliverLayout))
              .map((g) => g.columnCountOverride),
          everyElement(6),
        );

        // One press into the titles, one back.
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focused(), isNot(startsWith('person_')));
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focused(), 'person_tab_all');

        // Along the kinds into the availability filter; "Available" keeps
        // only the titles on the servers.
        await press(tester, LogicalKeyboardKey.arrowRight);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focused(), 'person_tab_appearances');
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focused(), 'person_availability_all');
        await press(tester, LogicalKeyboardKey.arrowRight);
        await press(tester, LogicalKeyboardKey.enter);
        expect(find.text('Shannon'), findsOneWidget);
        expect(find.text('Jack'), findsNothing);

        // UP from the filters is the biography button.
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focused(), 'person_biography');
      });
    }
  });

  testWidgets('a D-pad move in the grids scrolls gently, without a jump first', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    debugOckerLayoutOnThisHost = true;
    addTearDown(() {
      debugOckerLayoutOnThisHost = null;
      TvDetectionService.debugSetAppleTVOverride(null);
    });
    await pumpPage(tester, extraCredits: 30, tall: false);
    final position = tester.state<ScrollableState>(find.byType(Scrollable).last).position;

    await press(tester, LogicalKeyboardKey.arrowDown);
    for (var row = 0; row < 3; row++) {
      final before = position.pixels;
      final from = focused();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      // The focus has moved, but nothing has jumped yet: the poster scrolls
      // itself into place after the frame, animated.
      expect(focused(), isNot(from));
      expect(position.pixels, before, reason: 'row $row: no instant jump');
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(position.pixels, greaterThan(0));
  });

  testWidgets('LEFT and RIGHT at the edge of a grid row stay in the grid', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    debugOckerLayoutOnThisHost = true;
    addTearDown(() {
      debugOckerLayoutOnThisHost = null;
      TvDetectionService.debugSetAppleTVOverride(null);
    });
    await pumpPage(tester, extraCredits: 30, tall: false);
    final position = tester.state<ScrollableState>(find.byType(Scrollable).last).position;

    // Into the grids and down two rows, at the left edge.
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    final edge = focused();
    final scrolled = position.pixels;
    expect(edge, isNot(startsWith('person_')));
    expect(scrolled, greaterThan(0));

    // LEFT here once reached the home button: the stage came back and the
    // grids scrolled to the top.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focused(), edge);
    expect(position.pixels, scrolled);

    // Along to the row's right end, and once more.
    for (var i = 0; i < 5; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    final right = focused();
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), right);
    expect(focused(), isNot(startsWith('person_')));
  });

  testWidgets('elsewhere the scrolling page carries the same filters', (tester) async {
    await pumpPage(tester);

    expect(find.text('${t.actor.availability.missing}  2'), findsOneWidget);
    await tester.tap(find.text('${t.libraries.groupings.movies}  2'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Saturday Night Live'), findsNothing);
    expect(find.text('Argo'), findsOneWidget);
  });
}
