import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/watchlist_filter.dart';

import '../test_helpers/media_items.dart';

MediaItem _movie({bool watched = false}) =>
    testMediaItem(id: 'm', kind: MediaKind.movie, title: 'Film').withWatchedFlag(watched);

MediaItem _show({bool watched = false}) =>
    testMediaItem(id: 's', kind: MediaKind.show, title: 'Serie').withWatchedFlag(watched);

/// A title the provider said nothing about: no play count either way.
MediaItem _unknown() => testMediaItem(id: 'u', kind: MediaKind.movie, title: 'Unbekannt');

void main() {
  group('WatchlistFilter', () {
    test('an untouched filter narrows nothing', () {
      expect(WatchlistFilter.none.isEmpty, isTrue);
      expect(WatchlistFilter.none.matches(_movie()), isTrue);
      expect(WatchlistFilter.none.matches(_show(watched: true)), isTrue);
    });

    test('a kind is a kind, whatever the watch state', () {
      const movies = WatchlistFilter(type: WatchlistTypeFilter.movies);
      expect(movies.matches(_movie()), isTrue);
      expect(movies.matches(_movie(watched: true)), isTrue);
      expect(movies.matches(_show()), isFalse);

      const shows = WatchlistFilter(type: WatchlistTypeFilter.shows);
      expect(shows.matches(_show()), isTrue);
      expect(shows.matches(_movie()), isFalse);
    });

    test('watched and not watched are exact opposites', () {
      const watched = WatchlistFilter(status: WatchlistStatusFilter.watched);
      const unwatched = WatchlistFilter(status: WatchlistStatusFilter.unwatched);
      for (final item in [_movie(), _movie(watched: true), _show(), _show(watched: true), _unknown()]) {
        expect(
          watched.matches(item),
          isNot(unwatched.matches(item)),
          reason: 'every title belongs to exactly one of the two',
        );
      }
      expect(watched.matches(_movie(watched: true)), isTrue);
      expect(unwatched.matches(_movie()), isTrue);
    });

    test('a title no provider could answer for counts as unwatched', () {
      const unwatched = WatchlistFilter(status: WatchlistStatusFilter.unwatched);
      expect(unwatched.matches(_unknown()), isTrue);
      expect(const WatchlistFilter(status: WatchlistStatusFilter.watched).matches(_unknown()), isFalse);
    });

    test('a series left half-watched is not finished', () {
      final partial = testMediaItem(
        id: 'p',
        kind: MediaKind.show,
        title: 'Serie',
      ).copyWith(leafCount: 10, viewedLeafCount: 4);
      expect(const WatchlistFilter(status: WatchlistStatusFilter.unwatched).matches(partial), isTrue);
      expect(const WatchlistFilter(status: WatchlistStatusFilter.watched).matches(partial), isFalse);
    });

    test('both halves have to agree', () {
      const watchedMovies = WatchlistFilter(type: WatchlistTypeFilter.movies, status: WatchlistStatusFilter.watched);
      expect(watchedMovies.isEmpty, isFalse);
      expect(watchedMovies.matches(_movie(watched: true)), isTrue);
      expect(watchedMovies.matches(_movie()), isFalse);
      expect(watchedMovies.matches(_show(watched: true)), isFalse);
    });

    test('one half is replaced without disturbing the other', () {
      const start = WatchlistFilter(type: WatchlistTypeFilter.shows, status: WatchlistStatusFilter.watched);
      expect(start.withType(WatchlistTypeFilter.movies).status, WatchlistStatusFilter.watched);
      expect(start.withStatus(WatchlistStatusFilter.any).type, WatchlistTypeFilter.shows);
      expect(start.withType(WatchlistTypeFilter.shows), start, reason: 'value equality drives the grid refilter');
    });
  });
}
