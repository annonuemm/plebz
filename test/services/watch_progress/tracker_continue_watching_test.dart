import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/services/watch_progress/simkl_watch_state_parser.dart';
import 'package:plezy/services/watch_progress/tracker_continue_watching.dart';
import 'package:plezy/services/watch_progress/tracker_episode_list_client.dart';
import 'package:plezy/utils/external_ids.dart';

import '../../test_helpers/media_items.dart';

/// A server with one film and one series of two seasons × three episodes.
class _Server implements MediaServerClient {
  int episodeLookups = 0;

  @override
  Future<MediaItem?> fetchItem(String id) async =>
      id == 'film' ? testMediaItem(id: 'film', serverId: 'plex', title: 'Film') : null;

  @override
  Future<LibraryPage<MediaItem>> fetchPlayableDescendantsPage(
    String parentId, {
    int? start,
    int? size,
    Object? abort,
  }) async {
    episodeLookups++;
    final items = [
      if (parentId == 'show')
        for (var season = 1; season <= 2; season++)
          for (var number = 1; number <= 3; number++)
            testMediaItem(
              id: 's${season}e$number',
              serverId: 'plex',
              kind: MediaKind.episode,
              grandparentId: 'show',
              parentIndex: season,
              index: number,
            ),
    ];
    return LibraryPage(items: items, totalCount: items.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Map<String, Object?> _series(List<(int, int)> seen, {String lastWatched = '2026-10-01T20:00:00Z'}) => {
  'show': {
    'ids': {'simkl': 10, 'tvdb': 900},
  },
  'last_watched_at': lastWatched,
  'seasons': [
    for (final season in {for (final (s, _) in seen) s})
      {
        'number': season,
        'episodes': [
          for (final (s, e) in seen)
            if (s == season) {'number': e},
        ],
      },
  ],
};

/// A server holding eight series, each answering its episodes a moment late.
class _BusyServer implements MediaServerClient {
  int running = 0;
  int most = 0;

  @override
  Future<LibraryPage<MediaItem>> fetchPlayableDescendantsPage(
    String parentId, {
    int? start,
    int? size,
    Object? abort,
  }) async {
    running++;
    most = math.max(most, running);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    running--;
    final items = [
      for (var number = 1; number <= 3; number++)
        testMediaItem(
          id: '$parentId-e$number',
          serverId: 'plex',
          kind: MediaKind.episode,
          grandparentId: parentId,
          parentIndex: 1,
          index: number,
        ),
    ];
    return LibraryPage(items: items, totalCount: items.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// A server that lists episodes without their tracks, and only so.
class _LightServer extends _Server implements TrackerEpisodeListClient {
  int lightLookups = 0;

  @override
  Future<List<MediaItem>> fetchEpisodesWithoutStreams(String seriesId) async {
    lightLookups++;
    return (await super.fetchPlayableDescendantsPage(seriesId)).items;
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPlayableDescendantsPage(
    String parentId, {
    int? start,
    int? size,
    Object? abort,
  }) => throw StateError('the full list with every track');
}

/// A server whose items are films and series by their id's first word.
class _TitleServer implements MediaServerClient {
  @override
  Future<MediaItem?> fetchItem(String id) async =>
      testMediaItem(id: id, serverId: 'plex', kind: id.startsWith('series') ? MediaKind.show : MediaKind.movie);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  const index = {'film': ExternalIds(tmdb: 101), 'show': ExternalIds(tvdb: 900)};

  test('a paused film and the next episode of a series in progress, newest first', () async {
    final state = parseSimklWatchState(
      allItems: {
        'shows': [
          _series([(1, 1), (1, 2)]),
        ],
      },
      playback: [
        {
          'id': 1,
          'type': 'movie',
          'progress': 40,
          'paused_at': '2026-10-05T20:00:00Z',
          'movie': {
            'ids': {'tmdb': 101},
          },
        },
      ],
    );

    final rows = await TrackerContinueWatching(state: state, index: index).fetch(_Server());

    expect(rows.map((row) => row.id), ['film', 's1e3']);
  });

  test('a paused episode stands for its series; no second entry for it', () async {
    final state = parseSimklWatchState(
      allItems: {
        'shows': [
          _series([(1, 1), (1, 2)]),
        ],
      },
      playback: [
        {
          'id': 2,
          'type': 'episode',
          'progress': 10,
          'paused_at': '2026-10-05T21:00:00Z',
          'episode': {'season': 2, 'number': 1},
          'show': {
            'ids': {'tvdb': 900},
          },
        },
      ],
    );
    final server = _Server();

    final rows = await TrackerContinueWatching(state: state, index: index).fetch(server);

    expect(rows.map((row) => row.id), ['s2e1']);
    expect(server.episodeLookups, 1, reason: 'one series, asked once');
  });

  test('the next episode runs on into the next season and stops at the end', () async {
    Future<String?> next(List<(int, int)> seen) async {
      final state = parseSimklWatchState(
        allItems: {
          'shows': [_series(seen)],
        },
        playback: const [],
      );
      return (await TrackerContinueWatching(state: state, index: index).nextEpisodeOf(_Server(), 'show'))?.id;
    }

    expect(await next([(1, 1), (1, 2), (1, 3)]), 's2e1');
    expect(await next([(1, 1), (1, 3)]), 's2e1', reason: 'after the last seen, not a gap before it');
    expect(await next([(2, 3)]), isNull);
  });

  test('a series not started offers nothing; neither does a title this server lacks', () async {
    final state = parseSimklWatchState(
      allItems: {
        'shows': [
          {
            'show': {
              'ids': {'tvdb': 555},
            },
            'last_watched_at': '2026-10-01T20:00:00Z',
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
      },
      playback: const [],
    );
    final continueWatching = TrackerContinueWatching(state: state, index: index);

    expect(await continueWatching.nextEpisodeOf(_Server(), 'show'), isNull);
    expect(await continueWatching.fetch(_Server()), isEmpty);
  });

  test('series are asked a few at a time, not one after another', () async {
    final state = parseSimklWatchState(
      allItems: {
        'shows': [
          for (var i = 0; i < 8; i++)
            {
              'show': {
                'ids': {'simkl': 20 + i, 'tvdb': 800 + i},
              },
              'last_watched_at': '2026-10-0${i + 1}T20:00:00Z',
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
      },
      playback: const [],
    );
    final server = _BusyServer();
    final many = {for (var i = 0; i < 8; i++) 'show$i': ExternalIds(tvdb: 800 + i)};

    final rows = await TrackerContinueWatching(state: state, index: many).fetch(server);

    expect(rows.map((row) => row.id), [for (var i = 7; i >= 0; i--) 'show$i-e2']);
    expect(server.most, TrackerContinueWatching.parallelLookups);
  });

  test('a server that lists episodes without their tracks is asked that way', () async {
    final state = parseSimklWatchState(
      allItems: {
        'shows': [
          _series([(1, 1)]),
        ],
      },
      playback: const [],
    );
    final server = _LightServer();

    final next = await TrackerContinueWatching(state: state, index: index).nextEpisodeOf(server, 'show');

    expect(next?.id, 's1e2');
    expect(server.lightLookups, 1);
  });

  test('the titles watched last: newest first, each only as what the tracker named', () async {
    final state = parseSimklWatchState(
      allItems: {
        'movies': [
          {
            'movie': {
              'ids': {'simkl': 1, 'tmdb': 101},
            },
            'status': 'completed',
            'last_watched_at': '2026-10-01T20:00:00Z',
          },
          {
            'movie': {
              'ids': {'simkl': 2, 'tmdb': 102},
            },
            'status': 'plantowatch',
          },
        ],
        'shows': [
          _series([(1, 1)], lastWatched: '2026-10-03T20:00:00Z'),
        ],
      },
      playback: [
        {
          'id': 3,
          'type': 'movie',
          'progress': 30,
          'paused_at': '2026-10-04T20:00:00Z',
          'movie': {
            'ids': {'tmdb': 103},
          },
        },
      ],
    );
    const titles = {
      'film': ExternalIds(tmdb: 101),
      // A series that shares the film's TMDB number.
      'series-clash': ExternalIds(tmdb: 101),
      'listed': ExternalIds(tmdb: 102),
      'series': ExternalIds(tvdb: 900),
      'paused': ExternalIds(tmdb: 103),
    };

    final recent = await TrackerContinueWatching(state: state, index: titles).recentlyWatched(_TitleServer());

    expect(recent.map((item) => item.id), ['paused', 'series', 'film']);
  });
}
