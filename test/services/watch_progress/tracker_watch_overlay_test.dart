import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/watch_progress/simkl_watch_state_parser.dart';
import 'package:plezy/services/watch_progress/tracker_watch_overlay.dart';
import 'package:plezy/utils/external_ids.dart';

import '../../test_helpers/media_items.dart';

void main() {
  // What the profile's Simkl account says.
  final state = parseSimklWatchState(
    allItems: {
      'movies': [
        {
          'movie': {
            'ids': {'simkl': 1, 'tmdb': 101},
          },
          'status': 'completed',
          'last_watched_at': '2026-05-08T20:00:00Z',
        },
      ],
      'shows': [
        {
          'show': {
            'ids': {'simkl': 10, 'tvdb': 900},
          },
          'last_watched_at': '2026-05-09T20:00:00Z',
          'seasons': [
            {
              'number': 1,
              'episodes': [
                for (var number = 1; number <= 10; number++) {'number': number},
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
    },
    playback: [
      {
        'id': 7,
        'type': 'movie',
        'progress': 50,
        'paused_at': '2026-05-10T20:00:00Z',
        'movie': {
          'ids': {'tmdb': 102},
        },
      },
      {
        'id': 8,
        'type': 'episode',
        'progress': 25,
        'paused_at': '2026-05-10T21:00:00Z',
        'episode': {'season': 2, 'number': 2},
        'show': {
          'ids': {'tvdb': 900},
        },
      },
    ],
  );

  // What the server knows its titles by: film 'seen' is tmdb 101, 'paused'
  // tmdb 102, 'other' an id Simkl has never heard of; series 'show' tvdb 900.
  const ids = {
    'seen': ExternalIds(tmdb: 101),
    'paused': ExternalIds(tmdb: 102),
    'other': ExternalIds(tmdb: 999),
    'show': ExternalIds(tvdb: 900),
  };
  final overlay = TrackerWatchOverlay(state: state, idsOf: (serverId, itemId) => ids[itemId]);

  group('films', () {
    test('watched on Simkl is watched here, whatever the shared account says', () {
      final item = overlay.apply(testMediaItem(id: 'seen', serverId: 'plex', viewCount: 0));
      expect(item.isWatched, isTrue);
      expect(item.lastViewedAt, DateTime.utc(2026, 5, 8, 20).millisecondsSinceEpoch ~/ 1000);
    });

    test('paused on Simkl resumes at its share of this file\'s length', () {
      final item = overlay.apply(testMediaItem(id: 'paused', serverId: 'plex', durationMs: 7200000));
      expect(item.isWatched, isFalse);
      expect(item.viewOffsetMs, 3600000);
    });

    test('the shared account\'s state does not leak into the profile', () {
      final item = overlay.apply(
        testMediaItem(id: 'other', serverId: 'plex', viewCount: 3, viewOffsetMs: 5000, lastViewedAt: 1),
      );
      expect(item.isWatched, isFalse);
      expect(item.viewOffsetMs, isNull);
      expect(item.lastViewedAt, isNull);
    });

    test('a film the server named no ids for is unwatched too', () {
      expect(overlay.apply(testMediaItem(id: 'unknown', serverId: 'plex', viewCount: 1)).isWatched, isFalse);
    });
  });

  group('series', () {
    test('a series counts the episodes seen, no more than the server holds', () {
      final show = overlay.apply(
        testMediaItem(id: 'show', serverId: 'plex', kind: MediaKind.show, leafCount: 8, viewedLeafCount: 0),
      );
      expect(show.viewedLeafCount, 8);
      expect(show.isWatched, isTrue);
    });

    test('a season counts its own episodes', () {
      final season = overlay.apply(
        testMediaItem(id: 's2', serverId: 'plex', kind: MediaKind.season, parentId: 'show', index: 2, leafCount: 6),
      );
      expect(season.viewedLeafCount, 1);
      expect(season.isPartiallyWatched, isTrue);
    });

    test('an episode is found by its series and its numbers', () {
      MediaItem episode(int season, int number) => overlay.apply(
        testMediaItem(
          id: 'e$season$number',
          serverId: 'plex',
          kind: MediaKind.episode,
          grandparentId: 'show',
          parentIndex: season,
          index: number,
          durationMs: 2400000,
          viewCount: 1,
        ),
      );
      expect(episode(1, 4).isWatched, isTrue);
      expect(episode(2, 2).isWatched, isFalse);
      expect(episode(2, 2).viewOffsetMs, 600000);
      expect(episode(3, 1).isWatched, isFalse);
    });
  });

  test('music and other kinds pass untouched', () {
    final track = testMediaItem(id: 't', serverId: 'plex', kind: MediaKind.track, viewCount: 4);
    expect(identical(overlay.apply(track), track), isTrue);
  });

  group('this app\'s own changes, not yet echoed by the tracker', () {
    final at = DateTime.utc(2026, 10, 6, 20);
    TrackerWatchOverlay withPatches(Map<String, LocalWatchPatch> patches) =>
        TrackerWatchOverlay(state: state, idsOf: (serverId, itemId) => ids[itemId], patches: patches);
    MediaItem episode(String id, {int season = 3, int number = 1}) => testMediaItem(
      id: id,
      serverId: 'plex',
      kind: MediaKind.episode,
      parentId: 'season-3',
      grandparentId: 'show',
      parentIndex: season,
      index: number,
      durationMs: 2400000,
    );

    test('a film marked here is watched at once', () {
      final overlay = withPatches({'plex|other': LocalWatchPatch(watched: true, at: at)});
      expect(overlay.apply(testMediaItem(id: 'other', serverId: 'plex')).isWatched, isTrue);
    });

    test('a film unmarked here is unwatched, though the tracker still says watched', () {
      final overlay = withPatches({'plex|seen': LocalWatchPatch(watched: false, at: at)});
      expect(overlay.apply(testMediaItem(id: 'seen', serverId: 'plex')).isWatched, isFalse);
    });

    test('where playback was just left is where it resumes', () {
      final overlay = withPatches({'plex|e1': LocalWatchPatch(offsetMs: 90000, at: at)});
      final item = overlay.apply(episode('e1'));
      expect(item.viewOffsetMs, 90000);
      expect(item.isWatched, isFalse);
    });

    test('a season marked here reaches its episodes; a later mark on one episode wins', () {
      final overlay = withPatches({
        'plex|season-3': LocalWatchPatch(watched: true, at: at),
        'plex|e2': LocalWatchPatch(watched: false, at: at.add(const Duration(minutes: 1))),
      });
      expect(overlay.apply(episode('e1')).isWatched, isTrue);
      expect(overlay.apply(episode('e2', number: 2)).isWatched, isFalse);
      final season = overlay.apply(
        testMediaItem(
          id: 'season-3',
          serverId: 'plex',
          kind: MediaKind.season,
          parentId: 'show',
          index: 3,
          leafCount: 5,
        ),
      );
      expect(season.isWatched, isTrue);
    });
  });

  group('this device\'s change against what the tracker says later', () {
    MediaItem paused(TrackerWatchOverlay overlay) =>
        overlay.apply(testMediaItem(id: 'paused', serverId: 'plex', durationMs: 7200000));

    test('a position left here outlives the tracker\'s older pause', () {
      // Simkl's own pause is from 10 May; the viewer got further here in October.
      final overlay = TrackerWatchOverlay(
        state: state,
        idsOf: (serverId, itemId) => ids[itemId],
        patches: {'plex|paused': LocalWatchPatch(offsetMs: 6000000, at: DateTime.utc(2026, 10, 6))},
      );
      expect(paused(overlay).viewOffsetMs, 6000000);
    });

    test('the tracker\'s newer pause wins over an older change made here', () {
      // Watched on another device after this one's change.
      final overlay = TrackerWatchOverlay(
        state: state,
        idsOf: (serverId, itemId) => ids[itemId],
        patches: {'plex|paused': LocalWatchPatch(offsetMs: 6000000, at: DateTime.utc(2026, 5, 1))},
      );
      expect(paused(overlay).viewOffsetMs, 3600000);
    });
  });
}
