import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/redesign/ocker_poster_tile.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';

import '../test_helpers/prefs.dart';

/// What a poster says besides showing a picture — available, requested, when
/// the next episode airs — is a property of the poster, not of the card that
/// happens to draw it. The Ocker tile had its own idea of that for a while and
/// simply left the marks off; this is the guard against it drifting again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
  });

  final hub = MediaHub(id: 'h', title: 'Erkunden', type: 'mixed', items: const []);

  MediaItem itemWith(Map<String, dynamic> catalogJson) => MediaItem(
    id: 'c1',
    backend: MediaBackend.plex,
    kind: MediaKind.show,
    title: 'Serie',
    raw: {CatalogItem.rawKey: catalogJson},
  );

  Future<void> pump(WidgetTester tester, MediaItem item) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: Scaffold(
          body: Center(
            child: OckerPosterTile(
              item: item,
              hub: hub,
              index: 0,
              itemCount: 1,
              posterMode: EpisodePosterMode.seriesPoster,
              mixedHub: false,
              hideSpoilers: false,
              tileWidth: 210,
              tileHeight: 315,
              focusNode: FocusNode(debugLabel: 'tile'),
              resolveClient: (_) => null,
              onPlay: () {},
              onFocused: () {},
              neighbour: (_) => null,
              onExitUp: () {},
              onExitDown: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a title already on a server carries the check', (tester) async {
    await pump(
      tester,
      itemWith({
        'source': 'seerr',
        'kind': 'show',
        'title': 'Serie',
        'serverState': {'availability': 'available'},
      }),
    );

    expect(find.byKey(const Key('catalog-available-check')), findsOneWidget);
  });

  testWidgets('a title with a next episode says when it airs', (tester) async {
    await pump(
      tester,
      itemWith({
        'source': 'seerr',
        'kind': 'show',
        'title': 'Serie',
        'nextEpisode': {'airsAt': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String()},
      }),
    );

    expect(find.byKey(const Key('catalog-next-airing')), findsOneWidget);
  });

  testWidgets('the marks are set in mono, and only under this theme', (tester) async {
    // A countdown, a count and an availability word are labels, counters and
    // timecodes — the one job this design gives the mono family. Set in the
    // interface face they read as a sentence someone left on the artwork.
    await pump(
      tester,
      itemWith({
        'source': 'seerr',
        'kind': 'show',
        'title': 'Serie',
        'nextEpisode': {'airsAt': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String()},
      }),
    );

    final label = tester.widget<Text>(
      find.descendant(of: find.byKey(const Key('catalog-next-airing')), matching: find.byType(Text)),
    );
    expect(label.style?.fontFamily, 'Inter');
  });

  testWidgets('an ordinary title carries none of them', (tester) async {
    await pump(tester, MediaItem(id: 'm1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Film'));

    expect(find.byKey(const Key('catalog-available-check')), findsNothing);
    expect(find.byKey(const Key('catalog-next-airing')), findsNothing);
    expect(find.byKey(const Key('catalog-badges')), findsNothing);
  });
}
