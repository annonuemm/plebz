import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/ultra_blur_colors.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/redesign/ocker_rail_shell.dart';
import 'package:plezy/redesign/ultra_blur_backdrop.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/plex_client.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/tv_spotlight_background.dart';

import '../test_helpers/backend_client_fixtures.dart';
import '../test_helpers/http_fixtures.dart';
import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

const _colors = {'topLeft': '3d3021', 'topRight': '6e4d2d', 'bottomRight': '222c26', 'bottomLeft': '#1b1f1c'};

/// A Plex server answering the colours service, recording what it was asked.
({PlexClient client, List<String> asked}) _server(String serverId) {
  final asked = <String>[];
  final client = testPlexClient(
    serverId: ServerId(serverId),
    handler: (request) async {
      if (request.url.path != '/services/ultrablur/colors') return http.Response('not found', 404);
      asked.add(request.url.queryParameters['url']!);
      return jsonResponse({
        'MediaContainer': {
          'size': 1,
          'UltraBlurColors': [_colors],
        },
      });
    },
  );
  return (client: client, asked: asked);
}

void main() {
  setUpAll(() {
    PlexApiCache.initialize(AppDatabase.forTesting(NativeDatabase.memory()));
    LocaleSettings.setLocaleSync(AppLocale.en);
    return initializeDateFormatting('en');
  });

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    UltraBlurAmbient.debugClearCache();
  });

  test('the four corners are read from the server\'s hex, with or without a hash', () {
    final colors = UltraBlurColors.fromJson([_colors])!;
    expect(colors.topLeft, const Color(0xFF3D3021));
    expect(colors.bottomLeft, const Color(0xFF1B1F1C));
    expect(UltraBlurColors.fromJson({'topLeft': '3d3021'}), isNull);
    expect(UltraBlurColors.fromJson(const []), isNull);
  });

  test('the Plex client asks the colours service about the image it is given', () async {
    final server = _server('plex-1');
    final colors = await server.client.fetchUltraBlurColors('/library/metadata/7/art/1');
    expect(server.asked, ['/library/metadata/7/art/1']);
    expect(colors?.topRight, const Color(0xFF6E4D2D));
  });

  group('the ambient colours', () {
    testWidgets('follow a Plex title where focus stops, asking its own server once', (tester) async {
      final server = _server('plex-1');
      final ambient = UltraBlurAmbient((owner: (id) => id == 'plex-1' ? server.client : null, any: () => null));
      addTearDown(ambient.dispose);

      final film = testMediaItem(id: '7', serverId: 'plex-1', artPath: '/library/metadata/7/art/1');
      final passedOver = testMediaItem(id: '8', serverId: 'plex-1', artPath: '/library/metadata/8/art/1');
      ambient.report(passedOver);
      ambient.report(film);
      await tester.pump(UltraBlurAmbient.settleDelay);
      await tester.pump();

      // A run of the cursor costs one request, for where it stopped.
      expect(server.asked, ['/library/metadata/7/art/1']);
      expect(ambient.value?.topLeft, const Color(0xFF3D3021));

      ambient.report(passedOver);
      await tester.pump(UltraBlurAmbient.settleDelay);
      await tester.pump();
      ambient.report(film);
      await tester.pump(UltraBlurAmbient.settleDelay);
      await tester.pump();
      expect(server.asked, ['/library/metadata/7/art/1', '/library/metadata/8/art/1'], reason: 'the first is known');
    });

    testWidgets('a title that is not Plex\'s lets the ground show again', (tester) async {
      final server = _server('plex-1');
      final ambient = UltraBlurAmbient((owner: (_) => server.client, any: () => server.client));
      addTearDown(ambient.dispose);

      ambient.report(testMediaItem(id: '7', serverId: 'plex-1', artPath: '/library/metadata/7/art/1'));
      await tester.pump(UltraBlurAmbient.settleDelay);
      await tester.pump();
      expect(ambient.value, isNotNull);

      ambient.report(
        testMediaItem(
          id: 'j1',
          backend: MediaBackend.jellyfin,
          serverId: 'jelly-1',
          artPath: '/Items/j1/Images/Backdrop',
        ),
      );
      await tester.pump(UltraBlurAmbient.settleDelay);
      await tester.pump();
      expect(ambient.value, isNull);
      expect(server.asked, hasLength(1));
    });

    testWidgets('a title of Plex\'s catalogue is asked about on any Plex server, by its artwork\'s address', (
      tester,
    ) async {
      final server = _server('plex-1');
      final ambient = UltraBlurAmbient((owner: (_) => null, any: () => server.client));
      addTearDown(ambient.dispose);

      const art = 'https://metadata-static.plex.tv/a/b.jpg';
      ambient.report(
        const CatalogItem(
          source: CatalogSourceId.plex,
          kind: MediaKind.show,
          title: 'Explore',
          backdropUrl: art,
          ids: CatalogItemIds(plex: 'x'),
        ).toMediaItem(),
      );
      ambient.report(
        const CatalogItem(
          source: CatalogSourceId.trakt,
          kind: MediaKind.show,
          title: 'Not Plex',
          backdropUrl: 'https://image.example/c.jpg',
          ids: CatalogItemIds(trakt: 1),
        ).toMediaItem(),
      );
      await tester.pump(UltraBlurAmbient.settleDelay);
      await tester.pump();
      expect(server.asked, isEmpty, reason: 'the cursor ended on a title that is not Plex\'s');

      ambient.report(
        const CatalogItem(
          source: CatalogSourceId.plex,
          kind: MediaKind.show,
          title: 'Explore',
          backdropUrl: art,
          ids: CatalogItemIds(plex: 'x'),
        ).toMediaItem(),
      );
      await tester.pump(UltraBlurAmbient.settleDelay);
      await tester.pump();
      expect(server.asked, [art]);
      expect(ambient.value, isNotNull);
    });
  });

  testWidgets('the colours stay painted once the crossfade has finished', (tester) async {
    final colors = ValueNotifier<UltraBlurColors?>(null);
    addTearDown(colors.dispose);
    await tester.pumpWidget(UltraBlurLayer(colors: colors));

    Future<void> show(UltraBlurColors? value) async {
      // The 2x2 image is made by the engine, outside the fake clock.
      await tester.runAsync(() async {
        colors.value = value;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(UltraBlurLayer.crossfade);
      await tester.pump(const Duration(milliseconds: 16));
    }

    await show(UltraBlurColors.fromJson(_colors));
    await show(UltraBlurColors.fromJson({..._colors, 'topLeft': 'ffffff'}));
    expect(tester.takeException(), isNull);

    final painter = tester.widget<CustomPaint>(
      find.descendant(of: find.byType(UltraBlurLayer), matching: find.byType(CustomPaint)),
    );
    expect(painter.painter, isNotNull);
    // Painted again after the fade: nothing in it may be an image let go of.
    tester.renderObject<RenderBox>(find.byType(UltraBlurLayer)).markNeedsPaint();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('other destinations keep the theme\'s own ground, and their posters report to nothing', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final contentScope = FocusScopeNode();
    final railScope = FocusScopeNode();
    addTearDown(contentScope.dispose);
    addTearDown(railScope.dispose);
    await SettingsService.instance.write(SettingsService.glasUltraBlur, true);
    UltraBlurAmbient? seen;

    Future<void> pumpOn(NavigationTabId tab) => tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: OckerRailShell(
          tabs: NavigationTab.getVisibleTabs(isOffline: false),
          selectedTab: tab,
          onDestinationSelected: (_) {},
          onNavigateToContent: () {},
          expanded: false,
          railKey: GlobalKey(),
          railFocusScope: railScope,
          contentFocusScope: contentScope,
          content: Builder(
            builder: (context) {
              seen = UltraBlurScope.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    for (final tab in [NavigationTabId.libraries, NavigationTabId.watchlist, NavigationTabId.settings]) {
      await pumpOn(tab);
      await tester.pumpAndSettle();
      expect(find.byType(UltraBlurLayer), findsNothing, reason: tab.name);
      expect(seen, isNull, reason: tab.name);
    }
    for (final tab in OckerRailShell.ultraBlurDestinations) {
      await pumpOn(tab);
      await tester.pumpAndSettle();
      expect(find.byType(UltraBlurLayer), findsOneWidget, reason: tab.name);
      expect(seen, isNotNull, reason: tab.name);
    }
  });

  testWidgets('the switch lays the colours under the glass shell without disturbing the screen on it', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final contentScope = FocusScopeNode();
    final railScope = FocusScopeNode();
    addTearDown(contentScope.dispose);
    addTearDown(railScope.dispose);
    final screenKey = GlobalKey<_ScreenState>();

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: OckerRailShell(
          tabs: NavigationTab.getVisibleTabs(isOffline: false),
          selectedTab: NavigationTabId.discover,
          onDestinationSelected: (_) {},
          onNavigateToContent: () {},
          expanded: false,
          railKey: GlobalKey(),
          railFocusScope: railScope,
          contentFocusScope: contentScope,
          content: _Screen(key: screenKey),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UltraBlurLayer), findsNothing);
    final screen = screenKey.currentState;

    await SettingsService.instance.write(SettingsService.glasUltraBlur, true);
    await tester.pumpAndSettle();
    expect(find.byType(UltraBlurLayer), findsOneWidget);
    expect(screenKey.currentState, same(screen));

    await SettingsService.instance.write(SettingsService.glasUltraBlur, false);
    await tester.pumpAndSettle();
    expect(find.byType(UltraBlurLayer), findsNothing);
    expect(screenKey.currentState, same(screen));
  });

  testWidgets('under Flach the spotlight runs into the colours through its own two fades', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final ambient = UltraBlurAmbient((owner: (_) => null, any: () => null));
    addTearDown(ambient.dispose);
    const item = MediaItem.plex(id: 'movie_1', kind: MediaKind.movie, title: 'Flat Movie', year: 2024);

    Future<void> pump(AppThemeVariant variant, {required bool colours}) async {
      final spotlight = TvSpotlightBackground(
        item: item,
        client: null,
        allowNetwork: false,
        compact: true,
        contentTop: 80,
        contentBottom: 200,
      );
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true, variant: variant),
            home: Scaffold(
              body: SizedBox.expand(
                child: colours ? UltraBlurScope(ambient: ambient, child: spotlight) : spotlight,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    await pump(AppThemeVariant.flach, colours: true);
    final layers = tester.widgetList<UltraBlurLayer>(find.byType(UltraBlurLayer)).toList();
    expect(layers, hasLength(2), reason: 'one copy for the side fade, one for the foot');
    expect(layers.map((layer) => layer.dim), everyElement(TvSpotlightBackground.flatUltraBlurDim));
    for (final layer in find.byType(UltraBlurLayer).evaluate()) {
      expect(find.ancestor(of: find.byWidget(layer.widget), matching: find.byType(ShaderMask)), findsOneWidget);
    }

    await pump(AppThemeVariant.flach, colours: false);
    expect(find.byType(UltraBlurLayer), findsNothing);

    // Glas paints them under its shell and only lightens its scrims here.
    await pump(AppThemeVariant.glas, colours: true);
    expect(find.byType(UltraBlurLayer), findsNothing);
  });
}

class _Screen extends StatefulWidget {
  const _Screen({super.key});

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
