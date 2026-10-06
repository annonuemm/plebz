import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/services/watch_progress/simkl_watch_state_parser.dart';
import 'package:plezy/services/watch_progress/tracker_continue_watching.dart';
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
}
