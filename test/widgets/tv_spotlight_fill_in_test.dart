import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/tmdb/tmdb_fill_in_service.dart';
import 'package:plezy/services/tmdb/tmdb_client.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/tv_spotlight_background.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

/// The spotlight used to return the plain title before it ever built the widget
/// that performs the lookup, so the whole TMDB fill-in was dead on the one
/// surface it was written for. These tests pin the wiring, not the plumbing:
/// what matters is that rendering a bare item asks the service, and that what
/// comes back reaches the screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int requests;

  MediaItem catalogShow() => const CatalogItem(
    source: CatalogSourceId.simkl,
    kind: MediaKind.show,
    title: 'Eine Serie ohne Logo',
    ids: CatalogItemIds(tmdb: 1396),
  ).toMediaItem();

  Future<void> pumpSpotlight(WidgetTester tester, MediaItem item) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
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

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TmdbFillInService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    LocaleSettings.setLocaleSync(AppLocale.en);

    requests = 0;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    TmdbFillInService.initialize(
      db,
      clientFactory: (credential) => TmdbClient(
        credential,
        httpClient: MockClient((_) async {
          requests++;
          return http.Response(
            jsonEncode({
              'id': 1396,
              'overview': 'Was diese Serie erzählt.',
              'images': {
                'logos': [
                  {'file_path': '/logo.png', 'iso_639_1': 'en', 'vote_average': 5},
                ],
              },
            }),
            200,
          );
        }),
      ),
    );
    await SettingsService.getInstance();
  });

  tearDown(() async {
    TvDetectionService.debugSetAppleTVOverride(null);
    TmdbFillInService.resetForTesting();
    await db.close();
  });

  testWidgets('an item the server has no logo for is looked up', (tester) async {
    final settings = await SettingsService.getInstance();
    await tester.runAsync(() => settings.write(SettingsService.tmdbApiKey, 'test-key'));
    await settings.write(SettingsService.tmdbLogosEnabled, true);

    await pumpSpotlight(tester, catalogShow());

    expect(requests, 1, reason: 'the spotlight must reach the fill-in, not stop at the title text');
  });

  testWidgets('nothing is looked up while the switch is off', (tester) async {
    final settings = await SettingsService.getInstance();
    await tester.runAsync(() => settings.write(SettingsService.tmdbApiKey, 'test-key'));

    await pumpSpotlight(tester, catalogShow());

    expect(requests, 0);
    expect(find.text('Eine Serie ohne Logo'), findsOneWidget);
  });

  testWidgets('a description the catalog row lacked is shown once it arrives', (tester) async {
    final settings = await SettingsService.getInstance();
    await tester.runAsync(() => settings.write(SettingsService.tmdbApiKey, 'test-key'));
    await settings.write(SettingsService.tmdbLogosEnabled, true);

    await pumpSpotlight(tester, catalogShow());
    await tester.pump();

    expect(find.text('Was diese Serie erzählt.'), findsOneWidget);
  });

  testWidgets('an episode is never captioned with its series description', (tester) async {
    final settings = await SettingsService.getInstance();
    await tester.runAsync(() => settings.write(SettingsService.tmdbApiKey, 'test-key'));
    await settings.write(SettingsService.tmdbLogosEnabled, true);

    await pumpSpotlight(
      tester,
      testMediaItem(id: 'ep-1', kind: MediaKind.episode, serverId: 'server-1', grandparentId: 'series-1'),
    );
    await tester.pump();

    expect(find.text('Was diese Serie erzählt.'), findsNothing);
  });

  testWidgets('the title waits rather than flashing while a lookup runs', (tester) async {
    final settings = await SettingsService.getInstance();
    await tester.runAsync(() => settings.write(SettingsService.tmdbApiKey, 'test-key'));
    await settings.write(SettingsService.tmdbLogosEnabled, true);

    final gate = Completer<http.Response>();
    TmdbFillInService.initialize(
      db,
      clientFactory: (credential) {
        return TmdbClient(credential, httpClient: MockClient((_) => gate.future));
      },
    );

    await pumpSpotlight(tester, catalogShow());

    expect(
      find.text('Eine Serie ohne Logo'),
      findsNothing,
      reason: 'the plain name must not appear only to be replaced a moment later',
    );

    // A lookup that outlasts the grace still gets the title: an empty space
    // where a title belongs is worse than a title that changes.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Eine Serie ohne Logo'), findsOneWidget);

    gate.complete(
      http.Response(
        jsonEncode({
          'id': 1396,
          'images': {'logos': []},
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('an item that needs nothing is left alone', (tester) async {
    final settings = await SettingsService.getInstance();
    await tester.runAsync(() => settings.write(SettingsService.tmdbApiKey, 'test-key'));
    await settings.write(SettingsService.tmdbLogosEnabled, true);

    await pumpSpotlight(
      tester,
      catalogShow().copyWith(clearLogoPath: 'https://server/logo.png', summary: 'Was der Server erzählt.'),
    );

    expect(requests, 0, reason: 'the fill-in exists for gaps, not to second-guess the server');
    expect(find.text('Was der Server erzählt.'), findsOneWidget);
  });

  testWidgets('a missing description is fetched even when the logo is there', (tester) async {
    final settings = await SettingsService.getInstance();
    await tester.runAsync(() => settings.write(SettingsService.tmdbApiKey, 'test-key'));
    await settings.write(SettingsService.tmdbLogosEnabled, true);

    await pumpSpotlight(tester, catalogShow().copyWith(clearLogoPath: 'https://server/logo.png'));
    await tester.pump();

    expect(requests, 1);
    expect(find.text('Was diese Serie erzählt.'), findsOneWidget);
  });
}
