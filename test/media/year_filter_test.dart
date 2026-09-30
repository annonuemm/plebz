import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/year_filter.dart';

import '../test_helpers/media_items.dart';

void main() {
  group('a row outside the libraries', () {
    const eighties = YearRange(from: 1985, to: 1989);
    MediaHub hubOf(List<MediaItem> items) =>
        MediaHub(id: 'h', title: 'Row', type: 'mixed', items: items, size: items.length);

    test('keeps what belongs and drops the rest', () {
      final hub = hubOf([
        testMediaItem(id: 'a', kind: MediaKind.movie, title: 'In', year: 1986),
        testMediaItem(id: 'b', kind: MediaKind.movie, title: 'Out', year: 2001),
      ]);

      final filtered = applyYearFilterToHub(hub, movies: eighties, shows: YearRange.none);

      expect(filtered.items.map((item) => item.displayTitle), ['In']);
      expect(filtered.size, 1, reason: 'the count follows what is left, not what was fetched');
    });

    test('is handed back untouched when nothing is filtered', () {
      final hub = hubOf([testMediaItem(id: 'a', kind: MediaKind.movie, title: 'In', year: 1986)]);

      expect(identical(applyYearFilterToHub(hub, movies: eighties, shows: YearRange.none), hub), isTrue);
      expect(identical(applyYearFilterToHub(hub, movies: YearRange.none, shows: YearRange.none), hub), isTrue);
    });

    test('can end up empty, which is the caller\'s cue to drop it', () {
      final hub = hubOf([testMediaItem(id: 'b', kind: MediaKind.movie, title: 'Out', year: 2001)]);

      expect(applyYearFilterToHub(hub, movies: eighties, shows: YearRange.none).items, isEmpty);
    });
  });

  group('a stored pair becomes a range', () {
    test('an empty field is an open end, not the year zero', () {
      expect(yearRangeFrom(1985, 0), const YearRange(from: 1985));
      expect(yearRangeFrom(0, 2010), const YearRange(to: 2010));
      expect(yearRangeFrom(0, 0).isEmpty, isTrue);
    });

    test('a pair the wrong way round is read as the range meant', () {
      // Nobody types 2010 to 1997 in order to see nothing.
      expect(yearRangeFrom(2010, 1997), const YearRange(from: 1997, to: 2010));
    });
  });

  group('what a range admits', () {
    const eighties = YearRange(from: 1985, to: 1989);

    test('the ends belong to it', () {
      expect(eighties.allows(1985), isTrue);
      expect(eighties.allows(1989), isTrue);
      expect(eighties.allows(1984), isFalse);
      expect(eighties.allows(1990), isFalse);
    });

    test('an open end runs on', () {
      expect(const YearRange(from: 1985).allows(2026), isTrue);
      expect(const YearRange(from: 1985).allows(1984), isFalse);
      expect(const YearRange(to: 2010).allows(1932), isTrue);
      expect(const YearRange(to: 2010).allows(2011), isFalse);
    });

    test('a title without a year is kept', () {
      // An unknown year is not evidence of the wrong year, and dropping those
      // would make a library look damaged.
      expect(eighties.allows(null), isTrue);
    });

    test('an empty range admits everything', () {
      expect(YearRange.none.allows(1932), isTrue);
      expect(YearRange.none.allows(null), isTrue);
    });
  });

  group('the range as the servers take it', () {
    test('is written out year by year, ends included', () {
      expect(const YearRange(from: 1997, to: 2000).years(upperBound: 2026), [1997, 1998, 1999, 2000]);
    });

    test('an open end reaches the bound it is given', () {
      expect(const YearRange(from: 2024).years(upperBound: 2026), [2024, 2025, 2026]);
      expect(const YearRange(to: 1902).years(upperBound: 2026, lowerBound: 1900), [1900, 1901, 1902]);
    });

    test('an empty range writes nothing, so no filter is sent', () {
      expect(YearRange.none.years(upperBound: 2026), isEmpty);
    });

    test('an impossible range writes nothing rather than counting backwards', () {
      expect(const YearRange(from: 2030, to: 2020).years(upperBound: 2026), isEmpty);
    });
  });

  group('which range judges which item', () {
    const movies = YearRange(from: 1985, to: 1989);
    const shows = YearRange(from: 1997, to: 2010);

    bool allows(MediaKind kind, int? year) => yearFilterAllowsItem(
      testMediaItem(id: 'x', kind: kind, title: 'Title', year: year),
      movies: movies,
      shows: shows,
    );

    test('a film is judged by the film range', () {
      expect(allows(MediaKind.movie, 1986), isTrue);
      expect(allows(MediaKind.movie, 2001), isFalse);
    });

    test('a series by its own', () {
      expect(allows(MediaKind.show, 2001), isTrue);
      expect(allows(MediaKind.show, 1986), isFalse);
    });

    test('a season and an episode are never judged on their own year', () {
      // A series that ran for a decade would be cut in half: the 1999 show
      // whose fourth season aired in 2005 is still the 1999 show. The series
      // was judged when it was shown; what is under it follows.
      expect(allows(MediaKind.season, 2018), isTrue);
      expect(allows(MediaKind.episode, 2018), isTrue);
      expect(allows(MediaKind.episode, 1986), isTrue);
    });

    test('music and anything else is left alone', () {
      expect(allows(MediaKind.album, 1972), isTrue);
      expect(allows(MediaKind.track, 1972), isTrue);
      expect(allows(MediaKind.unknown, 1972), isTrue);
    });
  });
}
