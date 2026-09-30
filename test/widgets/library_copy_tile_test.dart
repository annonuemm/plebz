import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/library_copy_tile.dart';

import '../test_helpers/media_items.dart';

MediaItem _copy({String? libraryTitle, String? serverName, List<MediaVersion>? versions}) => testMediaItem(
  id: 'movie-1',
  kind: MediaKind.movie,
  title: 'Movie',
  serverId: 'server-1',
  serverName: serverName,
  libraryTitle: libraryTitle,
  libraryId: libraryTitle == null ? null : 'lib-1',
  mediaVersions: versions,
);

Future<void> _pumpTile(WidgetTester tester, MediaItem copy, {bool showsQuality = true}) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: LibraryCopyTile(copy: copy, onTap: () {}, showsQuality: showsQuality),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  group('bestVersionLabel', () {
    test('picks the tallest version, which is what tells two copies apart', () {
      final label = bestVersionLabel(
        _copy(
          versions: const [
            MediaVersion(id: 'a', videoResolution: '1080', videoCodec: 'h264', container: 'mkv'),
            MediaVersion(id: 'b', videoResolution: '4k', videoCodec: 'hevc', container: 'mkv'),
          ],
        ),
      );

      expect(label, startsWith('4K'));
    });

    test('is null when the backend reported no resolution at all', () {
      expect(
        bestVersionLabel(
          _copy(
            versions: const [MediaVersion(id: 'a', videoCodec: 'h264')],
          ),
        ),
        isNull,
      );
      expect(bestVersionLabel(_copy()), isNull);
    });

    test('a cropped 4K master is not mistaken for the 1080p copy', () {
      // The resolution fix this depends on: without it the 4K scope copy read
      // "1080p" and the comparison was wrong exactly where it matters.
      final label = bestVersionLabel(
        _copy(
          versions: const [MediaVersion(id: 'a', width: 3828, height: 1596, videoCodec: 'hevc')],
        ),
      );

      expect(label, startsWith('4K'));
    });
  });

  group('libraryCopyName', () {
    test('prefers the library, then the server, then the product name', () {
      expect(libraryCopyName(_copy(libraryTitle: 'Movies 4K', serverName: 'Living Room')), 'Movies 4K');
      expect(libraryCopyName(_copy(serverName: 'Living Room')), 'Living Room');
      expect(libraryCopyName(_copy()), isNotEmpty, reason: 'a copy is never listed nameless');
    });
  });

  group('LibraryCopyTile', () {
    testWidgets('names the library and states the quality it has', (tester) async {
      await _pumpTile(
        tester,
        _copy(
          libraryTitle: 'Main Movies',
          serverName: 'Living Room',
          versions: const [MediaVersion(id: 'a', videoResolution: '4k', videoCodec: 'hevc', container: 'mkv')],
        ),
      );

      expect(find.text('Main Movies'), findsOneWidget);
      // Quality and the server it sits on share the one subtitle line.
      expect(find.textContaining('4K'), findsOneWidget);
      expect(find.textContaining('Living Room'), findsOneWidget);
    });

    testWidgets('falls back to the server name when the library is unknown', (tester) async {
      await _pumpTile(tester, _copy(serverName: 'Basement'));

      expect(find.text('Basement'), findsOneWidget);
    });

    testWidgets('a copy with no quality information still renders its row', (tester) async {
      await _pumpTile(tester, _copy(libraryTitle: 'Movies'));

      expect(find.text('Movies'), findsOneWidget);
    });

    testWidgets('"Also available on" names the server, not the quality', (tester) async {
      await _pumpTile(
        tester,
        _copy(
          libraryTitle: 'Filme',
          serverName: 'Wohnzimmer',
          versions: const [MediaVersion(id: 'a', videoResolution: '1080', videoCodec: 'hevc', container: 'mkv')],
        ),
        showsQuality: false,
      );

      expect(find.text('Filme'), findsOneWidget);
      expect(find.text('Wohnzimmer'), findsOneWidget, reason: 'the server alone under the library');
      expect(find.textContaining('1080'), findsNothing);
    });
  });

  group('libraryCopyServer', () {
    test('is the server under a library name, and nothing where the name already is the server', () {
      expect(libraryCopyServer(_copy(libraryTitle: 'Filme', serverName: 'Wohnzimmer')), 'Wohnzimmer');
      expect(libraryCopyServer(_copy(serverName: 'Wohnzimmer')), isNull);
    });
  });
}
