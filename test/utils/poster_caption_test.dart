import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/utils/poster_caption.dart';

import '../test_helpers/media_items.dart';

/// The line under a poster's title (Plebz): the year, with a film's runtime or
/// a series' number of seasons.
void main() {
  group('in English', () {
    setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

    test("a film carries its runtime in whole minutes", () {
      final film = testMediaItem(id: 'f', kind: MediaKind.movie, year: 2024, durationMs: 166 * 60000 + 20000);
      expect(posterYearCaption(film), '2024 · 166 min');
    });

    test('a series carries its seasons, one or many', () {
      expect(
        posterYearCaption(testMediaItem(id: 's', kind: MediaKind.show, year: 2000, childCount: 3)),
        '2000 · 3 seasons',
      );
      expect(
        posterYearCaption(testMediaItem(id: 's', kind: MediaKind.show, year: 2000, childCount: 1)),
        '2000 · 1 season',
      );
    });

    test('what the server did not give leaves the year alone', () {
      expect(posterYearCaption(testMediaItem(id: 'f', kind: MediaKind.movie, year: 2024)), '2024');
      expect(posterYearCaption(testMediaItem(id: 'f', kind: MediaKind.movie, year: 2024, durationMs: 30000)), '2024');
      expect(posterYearCaption(testMediaItem(id: 's', kind: MediaKind.show, year: 2000, childCount: 0)), '2000');
      // A series' length is an episode's: never put under its poster.
      expect(posterYearCaption(testMediaItem(id: 's', kind: MediaKind.show, year: 2000, durationMs: 1500000)), '2000');
    });

    test('no year, no line', () {
      expect(posterYearCaption(testMediaItem(id: 'f', kind: MediaKind.movie, durationMs: 166 * 60000)), isNull);
    });
  });

  test('in German', () async {
    await LocaleSettings.setLocale(AppLocale.de);
    addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));
    expect(
      posterYearCaption(testMediaItem(id: 'f', kind: MediaKind.movie, year: 2024, durationMs: 166 * 60000)),
      '2024 · 166 Min',
    );
    expect(
      posterYearCaption(testMediaItem(id: 's', kind: MediaKind.show, year: 2000, childCount: 3)),
      '2000 · 3 Staffeln',
    );
    expect(
      posterYearCaption(testMediaItem(id: 's', kind: MediaKind.show, year: 2000, childCount: 1)),
      '2000 · 1 Staffel',
    );
  });
}
