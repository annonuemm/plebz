import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_person.dart';
import 'package:plezy/media/search_hit.dart';
import 'package:plezy/utils/search_relevance.dart';

import '../test_helpers/media_items.dart';

void main() {
  group('normalizeSearchText', () {
    test('normalizes canonical, compatibility, separator, and typography variants', () {
      expect(normalizeSearchText('Amélie'), normalizeSearchText('Ame\u0301lie'));
      expect(normalizeSearchText('Ａｍｅｌｉｅ'), normalizeSearchText('Amelie'));
      expect(normalizeSearchText('Spider\u00a0Man'), normalizeSearchText('Spider Man'));

      final expected = normalizeSearchText('Spider Man');
      for (final value in ['Spider-Man', 'Spider‑Man', 'Spider–Man', 'Spider—Man']) {
        expect(normalizeSearchText(value), expected, reason: value);
      }
    });

    test('preserves accents and script-significant marks', () {
      expect(normalizeSearchText('Cafe'), isNot(normalizeSearchText('Café')));
      expect(normalizeSearchText('Café'), normalizeSearchText('Cafe\u0301'));
      expect(normalizeSearchText('क'), isNot(normalizeSearchText('कि')));
      expect(normalizeSearchText('कि'), contains('ि'));
    });
  });

  group('media search ranking', () {
    test('does not give an English-only leading article bonus', () {
      // A leading article is trimmed before comparing (see the group below),
      // and the list it is trimmed from covers every language here — so these
      // three still score alike and the input order decides.
      final items = [
        testMediaItem(id: 'the', title: 'The Boys'),
        testMediaItem(id: 'les', title: 'Les Boys'),
        testMediaItem(id: 'los', title: 'Los Boys'),
      ];

      expect(_ids(rankMediaSearchResults(items, 'Boys')), ['the', 'les', 'los']);
      expect(_ids(rankMediaSearchResults(items.reversed.toList(), 'Boys')), ['los', 'les', 'the']);
    });

    test('keeps exact titles above longer prefixes', () {
      final items = [
        testMediaItem(id: 'longer', title: 'The Boys in the Boat'),
        testMediaItem(id: 'exact', title: 'The Boys'),
      ];

      expect(_ids(rankMediaSearchResults(items, 'The Boys')), ['exact', 'longer']);
    });

    test('preserves nullable-field weighting', () {
      final items = [
        testMediaItem(id: 'parent', parentTitle: 'Target'),
        testMediaItem(id: 'original', originalTitle: 'Target'),
      ];

      expect(_ids(rankMediaSearchResults(items, 'Target')), ['original', 'parent']);
    });
  });

  group('rankMediaSearchResults', () {
    test('ranks equivalent query forms identically and preserves normalized ties', () {
      final items = [
        testMediaItem(id: 'first', title: 'Spider-Man'),
        testMediaItem(id: 'second', title: 'Spider‑Man'),
        testMediaItem(id: 'third', title: 'Spider Man Returns'),
        testMediaItem(id: 'accented', title: 'Amélie'),
        testMediaItem(id: 'decomposed', title: 'Ame\u0301lie'),
      ];

      final asciiOrder = _ids(rankMediaSearchResults(items, 'Spider Man'));
      final compatibilityOrder = _ids(rankMediaSearchResults(items, 'Ｓｐｉｄｅｒ　Ｍａｎ'));
      final typographicOrder = _ids(rankMediaSearchResults(items, 'Spider—Man'));

      expect(compatibilityOrder, asciiOrder);
      expect(typographicOrder, asciiOrder);
      expect(asciiOrder.take(2), ['first', 'second']);
      expect(_ids(rankMediaSearchResults(items, 'Spider Man', limit: 1)), ['first']);
      expect(_ids(rankMediaSearchResults(items, 'Amélie')).take(2), ['accented', 'decomposed']);
    });

    test('bounded selection matches the unbounded full ordering for a large input', () {
      final items = <MediaItem>[
        for (var i = 0; i < 1000; i++)
          testMediaItem(
            id: 'item-$i',
            title: switch (i) {
              999 => 'Target',
              _ when i % 137 == 0 => 'Target result $i',
              _ when i % 41 == 0 => 'A Target result $i',
              _ => 'Candidate $i',
            },
          ),
      ];
      final expected = _fullyRankedIds(items, 'Target').take(100).toList();

      expect(_ids(rankMediaSearchResults(items, 'Target', limit: 100)), expected);
      expect(expected.first, 'item-999');
    });

    test('retains the earliest items when an equal-score run crosses the cap', () {
      final items = [for (var i = 0; i < 150; i++) testMediaItem(id: 'tie-$i', title: 'Same title')];

      expect(_ids(rankMediaSearchResults(items, 'Same title', limit: 100)), [for (var i = 0; i < 100; i++) 'tie-$i']);
    });

    test('preserves limit boundaries, full ordering, and empty-query input order', () {
      final items = [
        testMediaItem(id: 'prefix', title: 'Target Extended'),
        testMediaItem(id: 'exact', title: 'Target'),
        testMediaItem(id: 'contains', title: 'A Target Story'),
      ];
      final expected = _fullyRankedIds(items, 'Target');

      expect(rankMediaSearchResults(items, 'Target', limit: 0), isEmpty);
      expect(_ids(rankMediaSearchResults(items, 'Target', limit: 1)), ['exact']);
      expect(_ids(rankMediaSearchResults(items, 'Target', limit: items.length)), expected);
      expect(_ids(rankMediaSearchResults(items, 'Target', limit: items.length + 5)), expected);
      expect(_ids(rankMediaSearchResults(items, 'Target')), expected);
      expect(_ids(rankMediaSearchResults(items, '— ‑ !!!', limit: 2)), ['prefix', 'exact']);
    });

    test('keeps the negative-limit failure contract', () {
      final items = [testMediaItem(title: 'Target')];

      expect(() => rankMediaSearchResults(items, 'Target', limit: -1), throwsRangeError);
      expect(() => rankMediaSearchResults(items, '!!!', limit: -1), throwsRangeError);
    });
  });
  group('What kind of thing it is', () {
    // Nobody searches for an episode title, and every sitcom has one called
    // "Der Herr der Ringe". So the kind is a band, decided before the score:
    // a thing you set out to find sits above a part of one whatever their
    // names happen to do. The chip strip is there for the rare time someone
    // did want the episodes.
    test('puts the film above an episode of the same name', () {
      final ranked = rankMediaSearchResults([
        testMediaItem(id: 'ep', kind: MediaKind.episode, title: 'Matrix'),
        testMediaItem(id: 'film', kind: MediaKind.movie, title: 'Matrix'),
      ], 'Matrix');

      expect(ranked.first.id, 'film');
    });

    test('and does it whichever order the servers answered in', () {
      final ranked = rankMediaSearchResults([
        testMediaItem(id: 'film', kind: MediaKind.movie, title: 'Matrix'),
        testMediaItem(id: 'ep', kind: MediaKind.episode, title: 'Matrix'),
      ], 'Matrix');

      expect(ranked.first.id, 'film');
    });

    test('holds even where the episode is the better match', () {
      // This is the whole point and it is deliberate: a film the query only
      // appears inside still outranks an episode that matches it exactly. Any
      // bonus small enough to leave the rest of the ordering alone would be
      // too small to do this, which is why it is a band and not a bonus.
      final ranked = rankMediaSearchResults([
        testMediaItem(id: 'ep', kind: MediaKind.episode, title: 'Matrix'),
        testMediaItem(id: 'film', kind: MediaKind.movie, title: 'Die Matrix Revolutionen'),
      ], 'Matrix');

      expect(ranked.first.id, 'film');
    });

    test('ranks within a band exactly as before', () {
      // The band decides nothing among things of one kind — a search that
      // returns only episodes is ordered by how well they matched, as it was.
      final ranked = rankMediaSearchResults([
        testMediaItem(id: 'contains', kind: MediaKind.episode, title: 'Die Matrix Revolutionen'),
        testMediaItem(id: 'exact', kind: MediaKind.episode, title: 'Matrix'),
      ], 'Matrix');

      expect([for (final item in ranked) item.id], ['exact', 'contains']);
    });

    test('keeps the band when the result set is capped', () {
      // The bounded path keeps the best `limit` entries through a heap; it has
      // to weigh the band the same way the unbounded sort does, or a cap would
      // quietly throw away the films and keep the episodes.
      final items = [
        for (var i = 0; i < 60; i++) testMediaItem(id: 'ep-$i', kind: MediaKind.episode, title: 'Matrix'),
        testMediaItem(id: 'film', kind: MediaKind.movie, title: 'Die Matrix Revolutionen'),
      ];

      expect(rankMediaSearchResults(items, 'Matrix', limit: 10).first.id, 'film');
    });
  });
  group('The article nobody types', () {
    test('finds the film before an episode whose title is exactly the query', () {
      // The case that started this: a sitcom episode called "Herr der Ringe"
      // is an exact match, the film "Der Herr der Ringe" only a contains — and
      // the episode stood on top.
      final ranked = rankMediaSearchResults([
        testMediaItem(
          id: 'episode',
          kind: MediaKind.episode,
          title: 'Herr der Ringe',
          grandparentTitle: 'Raising Hope',
        ),
        testMediaItem(id: 'film', kind: MediaKind.movie, title: 'Der Herr der Ringe'),
      ], 'herr der ringe');

      expect(ranked.first.id, 'film');
    });

    test('works from the other side too', () {
      final ranked = rankMediaSearchResults([
        testMediaItem(id: 'other', kind: MediaKind.movie, title: 'Herr der Ringe Doku'),
        testMediaItem(id: 'film', kind: MediaKind.movie, title: 'Herr der Ringe'),
      ], 'der herr der ringe');

      expect(ranked.first.id, 'film');
    });

    test('still prefers the title that needed no trimming', () {
      // Type "Die Hard" and you get Die Hard, not something called "Hard".
      final ranked = rankMediaSearchResults([
        testMediaItem(id: 'hard', kind: MediaKind.movie, title: 'Hard'),
        testMediaItem(id: 'diehard', kind: MediaKind.movie, title: 'Die Hard'),
      ], 'die hard');

      expect(ranked.first.id, 'diehard');
    });

    test('only strips a whole word, and only at the front', () {
      // "Theater" does not begin with the article "the".
      final ranked = rankMediaSearchResults([
        testMediaItem(id: 'theater', kind: MediaKind.movie, title: 'Theater'),
        testMediaItem(id: 'ater', kind: MediaKind.movie, title: 'Ater'),
      ], 'ater');

      expect(ranked.first.id, 'ater');
    });
  });
  group('A year in the query', () {
    test('picks the right one of two films with one name', () {
      final ranked = rankMediaSearchResults([
        testMediaItem(id: 'lynch', kind: MediaKind.movie, title: 'Dune', year: 1984),
        testMediaItem(id: 'villeneuve', kind: MediaKind.movie, title: 'Dune', year: 2021),
      ], 'Dune 2021');

      expect(ranked.first.id, 'villeneuve');
    });

    test('matches the title on what is left, not on the whole string', () {
      // "Dune 2021" against the title "Dune" used to be a fuzzy partial, so
      // anything actually called "Dune 2021 ..." outscored the film itself.
      final ranked = rankMediaSearchResults([
        testMediaItem(id: 'trailer', kind: MediaKind.movie, title: 'Dune 2021 Trailer'),
        testMediaItem(id: 'film', kind: MediaKind.movie, title: 'Dune', year: 2021),
      ], 'Dune 2021');

      expect(ranked.first.id, 'film');
    });

    test('never drops a title whose year disagrees', () {
      // Backends are off by one on release years often enough that a year can
      // only ever add. A perfect title match with the wrong year still ranks
      // above a poor one with the right year.
      final ranked = rankMediaSearchResults([
        testMediaItem(id: 'other', kind: MediaKind.movie, title: 'Dune Prophecy', year: 2021),
        testMediaItem(id: 'film', kind: MediaKind.movie, title: 'Dune', year: 2020),
      ], 'Dune 2021');

      expect(ranked.first.id, 'film');
    });

    test('leaves a year that is the whole query alone', () {
      // "2001" is a film.
      final ranked = rankMediaSearchResults([
        testMediaItem(id: 'other', kind: MediaKind.movie, title: 'Sunshine', year: 2001),
        testMediaItem(id: 'odyssey', kind: MediaKind.movie, title: '2001', year: 1968),
      ], '2001');

      expect(ranked.first.id, 'odyssey');
    });

    test('leaves a number inside a title alone', () {
      final ranked = rankMediaSearchResults([
        testMediaItem(id: 'other', kind: MediaKind.movie, title: 'Blade Runner', year: 2049),
        testMediaItem(id: 'sequel', kind: MediaKind.movie, title: 'Blade Runner 2049', year: 2017),
      ], 'Blade Runner 2049');

      expect(ranked.first.id, 'sequel');
    });
  });

  group('rankSearchHits', () {
    test('a title outranks people whose names match the query the same way', () {
      // Every candidate starts with "Rick"; the shorter names earn the larger
      // closeness bonus, so at a title's full weight the actors came first.
      final hits = <SearchHit>[
        PersonSearchHit(_person('rick-zahn', 'Rick Zahn')),
        PersonSearchHit(_person('rick-james', 'Rick James')),
        MediaSearchHit(testMediaItem(id: 'rick-and-morty', kind: MediaKind.show, title: 'Rick and Morty')),
      ];

      expect(_hitIds(rankSearchHits(hits, 'Rick')).first, 'rick-and-morty');
    });

    test('an exact name and a name prefix still beat weaker title matches', () {
      final exactName = <SearchHit>[
        MediaSearchHit(testMediaItem(id: 'portrait', title: 'Christoph Waltz: Portrait of an Actor')),
        PersonSearchHit(_person('waltz', 'Christoph Waltz')),
      ];
      // A title that only contains the query. Not "The Nolan Variations": with
      // its article off, that one *starts* with the query, and the article
      // rule ranks it as the prefix match it is to anyone typing it.
      final namePrefix = <SearchHit>[
        MediaSearchHit(testMediaItem(id: 'variations', title: 'Variations on Nolan')),
        PersonSearchHit(_person('north', 'Nolan North')),
      ];

      expect(_hitIds(rankSearchHits(exactName, 'Christoph Waltz')), ['waltz', 'portrait']);
      expect(_hitIds(rankSearchHits(namePrefix, 'Nolan')), ['north', 'variations']);
    });
  });
}

List<String> _ids(Iterable<MediaItem> items) => [for (final item in items) item.id];

MediaPerson _person(String id, String name) =>
    MediaPerson(id: id, name: name, backend: MediaBackend.plex, serverId: ServerId('plex-1'));

List<String> _hitIds(Iterable<SearchHit> hits) => [
  for (final hit in hits)
    switch (hit) {
      MediaSearchHit(:final item) => item.id,
      PersonSearchHit(:final person) => person.id,
    },
];

List<String> _fullyRankedIds(List<MediaItem> items, String query) => _ids(rankMediaSearchResults(items, query));
