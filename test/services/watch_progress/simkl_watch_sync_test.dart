import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/services/trackers/simkl/simkl_client.dart';
import 'package:plezy/services/trackers/tracker_session.dart';
import 'package:plezy/services/watch_progress/simkl_watch_sync.dart';
import 'package:plezy/services/watch_progress/tracker_watch_state.dart';
import 'package:plezy/utils/external_ids.dart';

Map<String, Object?> _activities({required String all, String removed = 'r1', String playback = 'p1'}) => {
  'all': all,
  for (final kind in ['movies', 'tv_shows', 'anime']) kind: {'removed_from_list': removed, 'playback': playback},
};

Map<String, Object?> _show(int simkl, int tvdb, List<int> episodes) => {
  'show': {
    'ids': {'simkl': simkl, 'tvdb': tvdb},
  },
  'seasons': [
    {
      'number': 1,
      'episodes': [
        for (final number in episodes) {'number': number},
      ],
    },
  ],
};

/// A Simkl account the test scripts: what each sync endpoint answers next,
/// and every request asked of it.
class _Account {
  Map<String, Object?> activities = _activities(all: 'a1');
  Object? everything = {
    'shows': [
      _show(1, 100, [1]),
    ],
  };
  Object? changes = const {};
  Object? playback = const [];

  /// What `/sync/all-items/anime` answers; null makes it fail.
  Object? animeInTvdb;
  final asked = <Uri>[];

  SimklClient client() => SimklClient(
    const TrackerSession(accessToken: 'token', refreshToken: '', expiresAt: 0, createdAt: 0),
    onSessionInvalidated: () {},
    httpClient: MockClient((request) async {
      asked.add(request.url);
      final body = switch (request.url.path) {
        '/sync/activities' => activities,
        '/sync/playback' => playback,
        '/sync/all-items' => request.url.queryParameters.containsKey('date_from') ? changes : everything,
        '/sync/all-items/anime' when animeInTvdb != null => animeInTvdb,
        _ => null,
      };
      if (body == null) return http.Response('', 500);
      return http.Response(jsonEncode(body), 200, headers: const {'content-type': 'application/json'});
    }),
  );

  List<String> get paths => [
    for (final uri in asked) uri.queryParameters.containsKey('date_from') ? '${uri.path}?since' : uri.path,
  ];
}

void main() {
  late _Account account;
  late SimklWatchSync sync;

  setUp(() {
    account = _Account();
    final client = account.client();
    addTearDown(client.dispose);
    sync = SimklWatchSync(client);
  });

  test('the first sync reads everything, with watched episodes and paused sessions', () async {
    final state = await sync.refresh(TrackerWatchState.empty);

    expect(account.paths, ['/sync/activities', '/sync/playback', '/sync/all-items']);
    final everything = account.asked.last.queryParameters;
    expect(everything['extended'], 'full');
    expect(everything['include_all_episodes'], 'yes');
    expect(state.show(const ExternalIds(tvdb: 100))!.hasWatched(1, 1), isTrue);
    expect(state.syncMarks['all'], 'a1');
  });

  test('nothing changed: one quiet question, and the same state back', () async {
    final first = await sync.refresh(TrackerWatchState.empty);
    account.asked.clear();

    final second = await sync.refresh(first);

    expect(account.paths, ['/sync/activities']);
    expect(identical(second, first), isTrue);
  });

  test('a change brings only what changed since, merged in', () async {
    final first = await sync.refresh(TrackerWatchState.empty);
    account
      ..asked.clear()
      ..activities = _activities(all: 'a2')
      ..changes = {
        'shows': [
          _show(1, 100, [1, 2]),
          _show(2, 200, [1]),
        ],
      };

    final second = await sync.refresh(first);

    expect(account.paths, ['/sync/activities', '/sync/all-items?since']);
    expect(account.asked.last.queryParameters['date_from'], 'a1');
    expect(second.show(const ExternalIds(tvdb: 100))!.hasWatched(1, 2), isTrue);
    expect(second.show(const ExternalIds(tvdb: 200)), isNotNull);
    expect(second.syncMarks['all'], 'a2');
  });

  test('paused sessions are read again only when they moved', () async {
    final first = await sync.refresh(TrackerWatchState.empty);
    account
      ..asked.clear()
      ..activities = _activities(all: 'a2', playback: 'p2')
      ..playback = [
        {
          'id': 9,
          'type': 'episode',
          'progress': 50,
          'paused_at': '2026-10-06T20:00:00Z',
          'episode': {'season': 1, 'number': 2},
          'show': {
            'ids': {'tvdb': 100},
          },
        },
      ];

    final second = await sync.refresh(first);

    expect(account.paths, ['/sync/activities', '/sync/playback', '/sync/all-items?since']);
    expect(second.episodePlayback(const ExternalIds(tvdb: 100), 1, 2)!.progress, 50);
  });

  test('a title taken off a list: everything again, so it is gone here too', () async {
    final first = await sync.refresh(TrackerWatchState.empty);
    account
      ..asked.clear()
      ..activities = _activities(all: 'a2', removed: 'r2')
      ..everything = const {};

    final second = await sync.refresh(first);

    expect(account.paths, ['/sync/activities', '/sync/playback', '/sync/all-items']);
    expect(second.shows, isEmpty);
  });

  group('anime', () {
    Map<String, Object?> anime(List<Map<String, Object?>> episodes) => {
      'anime': [
        {
          'show': {
            'ids': {'simkl': 30, 'tvdb': 3000},
          },
          'seasons': [
            {'number': 1, 'episodes': episodes},
          ],
        },
      ],
    };

    test('is asked again in TVDB numbering, and read in it', () async {
      account
        ..everything = anime([
          {'number': 14},
        ])
        ..animeInTvdb = anime([
          {
            'number': 14,
            'tvdb': {'season': 2, 'episode': 1},
          },
        ]);

      final state = await sync.refresh(TrackerWatchState.empty);

      expect(account.asked.last.path, '/sync/all-items/anime');
      expect(account.asked.last.queryParameters['extended'], 'full_anime_seasons');
      expect(state.show(const ExternalIds(tvdb: 3000))!.hasWatched(2, 1), isTrue);
    });

    test('keeps Simkl\'s own numbering when the second answer fails or brings no episodes', () async {
      account.everything = anime([
        {'number': 14},
      ]);
      final failed = await sync.refresh(TrackerWatchState.empty);
      expect(failed.show(const ExternalIds(tvdb: 3000))!.hasWatched(1, 14), isTrue);

      account.animeInTvdb = {
        'anime': [
          {
            'show': {
              'ids': {'simkl': 30},
            },
          },
        ],
      };
      final empty = await sync.refresh(TrackerWatchState.empty);
      expect(empty.show(const ExternalIds(tvdb: 3000))!.hasWatched(1, 14), isTrue);
    });
  });
}
