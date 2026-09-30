import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_search_grouping.dart';
import 'package:plezy/media/media_version.dart';

import '../test_helpers/media_items.dart';

/// A search across servers returns a row per *file*. The same film in a 1080p
/// library, a 4K library and an original-language library is three rows with
/// identical scores, sitting next to each other and spending the result budget
/// three times on one title. These are the rules that fold them into one — and
/// the rules that stop them folding where that would hide something.
void main() {
  MediaVersion version({required int height, String? label}) =>
      MediaVersion(id: 'v$height', videoResolution: label, width: height * 16 ~/ 9, height: height);

  group('Folding copies', () {
    test('folds every copy that shares a Plex guid', () {
      final groups = groupMediaSearchCopies([
        testMediaItem(id: 'hd', guid: 'plex://movie/abc', title: 'Dune', year: 2021, libraryTitle: 'Filme'),
        testMediaItem(id: 'uhd', guid: 'plex://movie/abc', title: 'Dune', year: 2021, libraryTitle: 'Filme - 4K'),
        testMediaItem(id: 'ov', guid: 'plex://movie/abc', title: 'Dune', year: 2021, libraryTitle: 'Filme - O-Ton'),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.copies, hasLength(3));
    });

    test('stands the row on the best copy', () {
      // What OK opens. `compareLibraryCopies` already says which that is —
      // highest resolution — and the search must not disagree with the chooser
      // on the page it leads to.
      final groups = groupMediaSearchCopies([
        testMediaItem(id: 'hd', guid: 'g', title: 'Dune', mediaVersions: [version(height: 1080)]),
        testMediaItem(id: 'uhd', guid: 'g', title: 'Dune', mediaVersions: [version(height: 2160)]),
      ]);

      expect(groups.single.best.id, 'uhd');
    });

    test('folds Jellyfin copies, whose guid is their own id', () {
      // The Jellyfin mapper fills `guid` with the item id — unique per file.
      // Trusting it gave every copy a group of its own, which is how two
      // rows for one film in an HD and a 4K library survived the fold.
      final groups = groupMediaSearchCopies([
        testMediaItem(
          id: 'hd',
          backend: MediaBackend.jellyfin,
          guid: 'hd',
          title: 'Schindlers Liste',
          year: 1993,
          libraryTitle: 'HD Filme',
        ),
        testMediaItem(
          id: 'uhd',
          backend: MediaBackend.jellyfin,
          guid: 'uhd',
          title: 'Schindlers Liste',
          year: 1993,
          libraryTitle: '4K Filme',
        ),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.copies, hasLength(2));
    });

    test('folds across servers on kind, title and year where there is no guid', () {
      // Jellyfin search rows carry no external ids: the field set that would
      // bring them makes a library page crawl. This is what is left.
      final groups = groupMediaSearchCopies([
        testMediaItem(id: 'a', title: 'Arrival', year: 2016, serverId: 's1'),
        testMediaItem(id: 'b', title: 'Arrival', year: 2016, serverId: 's2'),
      ]);

      expect(groups, hasLength(1));
    });

    test('will not guess without a year', () {
      // Two rows too many is a nuisance. A wrong fold hides a title the viewer
      // owns, so the guess is only made where the evidence is there.
      expect(
        groupMediaSearchCopies([
          testMediaItem(id: 'a', title: 'Arrival', serverId: 's1'),
          testMediaItem(id: 'b', title: 'Arrival', serverId: 's2'),
        ]),
        hasLength(2),
      );
    });

    test('keeps different years, different kinds and different titles apart', () {
      final groups = groupMediaSearchCopies([
        testMediaItem(id: 'film', kind: MediaKind.movie, title: 'Dune', year: 1984),
        testMediaItem(id: 'remake', kind: MediaKind.movie, title: 'Dune', year: 2021),
        testMediaItem(id: 'serie', kind: MediaKind.show, title: 'Dune', year: 2021),
      ]);

      expect(groups, hasLength(3));
    });

    test('keeps two episodes with one name apart unless they are the same episode', () {
      final groups = groupMediaSearchCopies([
        testMediaItem(
          id: 'e1',
          kind: MediaKind.episode,
          title: 'Pilot',
          year: 2008,
          grandparentTitle: 'Breaking Bad',
          parentIndex: 1,
          index: 1,
        ),
        testMediaItem(
          id: 'e2',
          kind: MediaKind.episode,
          title: 'Pilot',
          year: 2008,
          grandparentTitle: 'Lost',
          parentIndex: 1,
          index: 1,
        ),
        testMediaItem(
          id: 'e1-copy',
          kind: MediaKind.episode,
          title: 'Pilot',
          year: 2008,
          grandparentTitle: 'Breaking Bad',
          parentIndex: 1,
          index: 1,
        ),
      ]);

      expect(groups, hasLength(2));
    });

    test('never folds unmatched files together', () {
      // Plex's personal-media agent gives every file its own guid. Nothing
      // about two unmatched files says they are the same work.
      final groups = groupMediaSearchCopies([
        testMediaItem(id: 'a', guid: 'tv.plex.agents.none://a', title: 'Urlaub', year: 2019),
        testMediaItem(id: 'b', guid: 'tv.plex.agents.none://b', title: 'Urlaub', year: 2019),
      ]);

      expect(groups, hasLength(2));
    });

    test('keeps the order the servers answered in', () {
      final groups = groupMediaSearchCopies([
        testMediaItem(id: 'first', title: 'A', year: 2000),
        testMediaItem(id: 'second', title: 'B', year: 2000),
      ]);

      expect([for (final group in groups) group.best.id], ['first', 'second']);
    });
  });

  group('What the row says it stands for', () {
    String fallback(int count) => '$count Kopien';

    test('counts the resolutions when every copy knows one', () {
      final label = mediaSearchCopiesLabel([
        testMediaItem(
          id: 'a',
          mediaVersions: [version(height: 1080, label: '1080')],
        ),
        testMediaItem(
          id: 'b',
          mediaVersions: [version(height: 1080, label: '1080')],
        ),
        testMediaItem(
          id: 'c',
          mediaVersions: [version(height: 2160, label: '4k')],
        ),
      ], fallbackLabel: fallback);

      // A count only where it is more than one: a column of "1 ×" says nothing.
      expect(label, '2 × 1080p · 4K');
    });

    test('names the libraries when a copy cannot say what it is', () {
      // A Jellyfin row has no media sources — guessing at a quality it cannot
      // see would be worse than saying where the copies are.
      final label = mediaSearchCopiesLabel([
        testMediaItem(
          id: 'a',
          libraryTitle: 'Filme',
          mediaVersions: [version(height: 1080, label: '1080')],
        ),
        testMediaItem(id: 'b', libraryTitle: 'Filme - 4K'),
      ], fallbackLabel: fallback);

      expect(label, 'Filme · Filme - 4K');
    });

    test('falls back to a count when it knows neither', () {
      final label = mediaSearchCopiesLabel([testMediaItem(id: 'a'), testMediaItem(id: 'b')], fallbackLabel: fallback);

      expect(label, '2 Kopien');
    });

    test('says nothing about a single copy', () {
      expect(mediaSearchCopiesLabel([testMediaItem(id: 'a')], fallbackLabel: fallback), isNull);
    });
  });
}
