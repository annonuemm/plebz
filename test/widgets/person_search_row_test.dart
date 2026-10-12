import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart' show CardShape;
import 'package:plezy/media/media_person.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/catalog_person_screen.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/media_card_list_layout.dart';
import 'package:plezy/widgets/person_search_row.dart';
import 'package:provider/provider.dart';

import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';

/// A connected catalog source that only answers who it is.
class _IdOnlySource implements CatalogSource {
  _IdOnlySource(this.id);

  @override
  final CatalogSourceId id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedSources extends CatalogSourcesProvider {
  _FixedSources(this.sources);

  final List<CatalogSource> sources;

  @override
  List<CatalogSource> get connectedSources => sources;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  testWidgets('a photo still loading keeps the avatar slot inside an unbounded list', (tester) async {
    // Search rows sit in a SliverList, which leaves the row's height
    // unbounded. While the network photo loads, the loading placeholder
    // fills whatever box it is given; an unsized avatar slot handed it an
    // infinite one, and the failed layout blanked the whole search screen.
    await _pumpRow(tester);

    expect(tester.takeException(), isNull);
    final avatar = tester.getSize(find.byType(ClipOval));
    expect(avatar.width.isFinite, isTrue);
    expect(avatar.height, avatar.width);
  });

  testWidgets('a person row is shorter than a media row and lines its name up with titles', (tester) async {
    await _pumpRow(tester);

    final density = SettingsService.instance.read(SettingsService.libraryDensity);
    final squareMediaRowHeight = MediaCardListLayout.estimatedRowHeight(density: density, shape: CardShape.square);
    final mediaTitleStart = MediaCardListLayout.padding + MediaCardListLayout.basePosterWidth(density) + 12;
    expect(tester.getSize(find.byType(PersonSearchRow)).height, lessThan(squareMediaRowHeight));
    expect(tester.getTopLeft(find.text('Christoph Waltz')).dx, mediaTitleStart);
  });

  group('where a hit opens (Plebz)', () {
    testWidgets('with a Plex account it opens the page a title\'s cast opens', (tester) async {
      await _pumpRowWithSources(tester, [_IdOnlySource(CatalogSourceId.plex)]);

      await tester.tap(find.text('Christoph Waltz'));
      await tester.pumpAndSettle();

      final page = tester.widget<CatalogPersonScreen>(find.byType(CatalogPersonScreen));
      expect(page.name, 'Christoph Waltz');
      expect(page.thumbUrl, 'https://example.invalid/christoph-waltz.jpg');
    });

    testWidgets('a picture only the server can resolve is left to the Plex page', (tester) async {
      await _pumpRowWithSources(tester, [_IdOnlySource(CatalogSourceId.plex)], thumbPath: '/library/people/38797.jpg');

      await tester.tap(find.text('Christoph Waltz'));
      await tester.pumpAndSettle();

      expect(tester.widget<CatalogPersonScreen>(find.byType(CatalogPersonScreen)).thumbUrl, isNull);
    });

    testWidgets('without a Plex account the server\'s own list stays', (tester) async {
      late BuildContext withoutProvider;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            withoutProvider = context;
            return const SizedBox();
          },
        ),
      );
      expect(plexPersonPageAvailable(withoutProvider), isFalse);

      final sources = _FixedSources([_IdOnlySource(CatalogSourceId.trakt)]);
      addTearDown(sources.dispose);
      late BuildContext withTraktOnly;
      await tester.pumpWidget(
        ChangeNotifierProvider<CatalogSourcesProvider>.value(
          value: sources,
          child: Builder(
            builder: (context) {
              withTraktOnly = context;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(plexPersonPageAvailable(withTraktOnly), isFalse);
    });
  });
}

Future<void> _pumpRowWithSources(
  WidgetTester tester,
  List<CatalogSource> connected, {
  String thumbPath = 'https://example.invalid/christoph-waltz.jpg',
}) async {
  final sources = _FixedSources(connected);
  final servers = testMultiServer();
  addTearDown(sources.dispose);
  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<CatalogSourcesProvider>.value(value: sources),
          ChangeNotifierProvider<MultiServerProvider>.value(value: servers.provider),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: ListView(
              children: [
                PersonSearchRow(
                  person: MediaPerson(
                    id: '38797',
                    name: 'Christoph Waltz',
                    thumbPath: thumbPath,
                    credit: PersonCredit.actor,
                    backend: MediaBackend.plex,
                    serverId: ServerId('plex-1'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpRow(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      theme: monoTheme(dark: true),
      home: Scaffold(
        body: ListView(
          children: [
            PersonSearchRow(
              person: MediaPerson(
                id: '38797',
                name: 'Christoph Waltz',
                thumbPath: 'https://example.invalid/christoph-waltz.jpg',
                credit: PersonCredit.actor,
                backend: MediaBackend.plex,
                serverId: ServerId('plex-1'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
