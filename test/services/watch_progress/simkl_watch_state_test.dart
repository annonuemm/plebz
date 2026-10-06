import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/watch_progress/simkl_watch_state_parser.dart';
import 'package:plezy/services/watch_progress/tracker_watch_state.dart';
import 'package:plezy/utils/external_ids.dart';

const _allItems = {
  'movies': [
    {
      'movie': {
        'title': 'Seen',
        'ids': {'simkl': 1, 'imdb': 'tt001', 'tmdb': 101},
      },
      'status': 'completed',
      'last_watched_at': '2026-05-08T20:00:00Z',
    },
    {
      'movie': {
        'title': 'Wanted',
        'ids': {'simkl': 2, 'tmdb': 102},
      },
      'status': 'plantowatch',
    },
  ],
  'shows': [
    {
      'show': {
        'title': 'Series',
        'ids': {'simkl': 10, 'tvdb': 900, 'imdb': 'tt900'},
      },
      'status': 'watching',
      'last_watched_at': '2026-05-08T14:00:00Z',
      'seasons': [
        {
          'number': 1,
          'episodes': [
            {'number': 1, 'watched_at': '2026-05-01T20:00:00Z'},
            {'number': 2, 'watched_at': '2026-05-02T20:00:00Z'},
          ],
        },
        {
          'number': 2,
          'episodes': [
            {'number': 1},
          ],
        },
      ],
    },
  ],
  'anime': [
    {
      'show': {
        'title': 'Anime',
        'ids': {'simkl': 20, 'tmdb': 777},
      },
      'status': 'completed',
      'seasons': [
        {
          'number': 1,
          'episodes': [
            {'number': 1},
          ],
        },
      ],
    },
  ],
};

const _playback = [
  {
    'id': 5001,
    'type': 'episode',
    'progress': 75,
    'paused_at': '2026-05-08T20:15:00Z',
    'episode': {'number': 3, 'season': 2},
    'show': {
      'ids': {'simkl': 10, 'tvdb': 900},
    },
  },
  {
    'id': 5002,
    'type': 'movie',
    'progress': 45.5,
    'paused_at': '2026-05-08T21:00:00Z',
    'movie': {
      'ids': {'simkl': 2, 'tmdb': 102},
    },
  },
];

void main() {
  final state = parseSimklWatchState(allItems: _allItems, playback: _playback, syncMarks: const {'all': 'stamp-1'});

  group('reading Simkl', () {
    test('a completed film is watched, a wanted one only listed', () {
      expect(state.movie(const ExternalIds(imdb: 'tt001'))!.isWatched, isTrue);
      expect(state.movie(const ExternalIds(tmdb: 101))!.watchedAt, DateTime.utc(2026, 5, 8, 20));
      expect(state.movie(const ExternalIds(tmdb: 102))!.isWatched, isFalse);
      expect(state.movie(const ExternalIds(tmdb: 999)), isNull);
    });

    test('a series knows its watched episodes by season, under any of its ids', () {
      final show = state.show(const ExternalIds(tvdb: 900))!;
      expect(identical(show, state.show(const ExternalIds(imdb: 'tt900'))), isTrue);
      expect(show.hasWatched(1, 2), isTrue);
      expect(show.hasWatched(1, 3), isFalse);
      expect(show.watchedIn(1), 2);
      expect(show.watchedCount, 3);
    });

    test('anime counts as a series', () {
      expect(state.show(const ExternalIds(tmdb: 777))!.hasWatched(1, 1), isTrue);
    });

    test('paused sessions are found by film, or by series and episode', () {
      final episode = state.episodePlayback(const ExternalIds(tvdb: 900), 2, 3)!;
      expect(episode.progress, 75);
      expect(episode.positionIn(const Duration(minutes: 40)), const Duration(minutes: 30));
      expect(state.episodePlayback(const ExternalIds(tvdb: 900), 2, 4), isNull);
      expect(state.moviePlayback(const ExternalIds(tmdb: 102))!.progress, 45.5);
    });

    test('the state survives a round trip to disk', () {
      final back = TrackerWatchState.fromJson(state.toJson());
      expect(back.syncMarks, {'all': 'stamp-1'});
      expect(back.show(const ExternalIds(tvdb: 900))!.watchedCount, 3);
      expect(back.movie(const ExternalIds(tmdb: 101))!.isWatched, isTrue);
      expect(back.episodePlayback(const ExternalIds(tvdb: 900), 2, 3)!.key, '5001');
    });

    test('rubbish is skipped, not thrown', () {
      final odd = parseSimklWatchState(
        allItems: {
          'movies': [
            'x',
            {'movie': {}},
            {
              'movie': {'ids': {}},
            },
          ],
          'shows': 7,
        },
        playback: [
          {'id': 1},
        ],
      );
      expect(odd.movies, isEmpty);
      expect(odd.shows, isEmpty);
      expect(odd.playback, isEmpty);
    });
  });

  group('merging what changed', () {
    test('a changed title replaces its entry, the rest stays, paused sessions follow when given', () {
      final merged = mergeSimklChanges(
        state,
        changedItems: {
          'shows': [
            {
              'show': {
                'ids': {'simkl': 10, 'tvdb': 900},
              },
              'seasons': [
                {
                  'number': 2,
                  'episodes': [
                    {'number': 1},
                    {'number': 2},
                    {'number': 3},
                  ],
                },
              ],
            },
          ],
        },
        playback: const [],
        syncMarks: const {'all': 'stamp-2'},
      );
      expect(merged.syncMarks, {'all': 'stamp-2'});
      expect(merged.show(const ExternalIds(tvdb: 900))!.hasWatched(2, 3), isTrue);
      expect(merged.shows, hasLength(2));
      expect(merged.movies, hasLength(2));
      expect(merged.playback, isEmpty);
    });

    test('without new paused sessions the old ones are kept', () {
      final merged = mergeSimklChanges(state, changedItems: const {});
      expect(merged.playback, hasLength(2));
      expect(merged.syncMarks, {'all': 'stamp-1'});
    });
  });

  test('an anime episode in TVDB numbering is filed under it', () {
    final anime = parseSimklWatchState(
      allItems: {
        'anime': [
          {
            'show': {
              'ids': {'simkl': 30, 'tvdb': 3000},
            },
            'seasons': [
              {
                'number': 1,
                'episodes': [
                  {
                    'number': 14,
                    'tvdb': {'season': 2, 'episode': 1},
                  },
                  {'number': 15},
                ],
              },
            ],
          },
        ],
      },
      playback: [
        {
          'id': 3,
          'type': 'episode',
          'progress': 20,
          'paused_at': '2026-10-06T20:00:00Z',
          'episode': {
            'season': 1,
            'number': 16,
            'tvdb': {'season': 2, 'episode': 3},
          },
          'anime': {
            'ids': {'tvdb': 3000},
          },
        },
      ],
    );
    final show = anime.show(const ExternalIds(tvdb: 3000))!;
    expect(show.hasWatched(2, 1), isTrue);
    expect(show.hasWatched(1, 14), isFalse);
    expect(show.hasWatched(1, 15), isTrue, reason: 'without a TVDB block, Simkl\'s own numbers stand');
    expect(anime.episodePlayback(const ExternalIds(tvdb: 3000), 2, 3)?.progress, 20);
  });
}
