import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/models/catalog/catalog_metadata.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/catalog/catalog_watchlist_machinery.dart';
import 'package:plezy/services/catalog/plex_catalog_source.dart';
import 'package:plezy/services/plex_discover_client.dart';
import 'package:plezy/utils/external_ids.dart';

import '../../test_helpers/http_fixtures.dart';

const _session = PlexDiscoverSession(accessToken: 'profile-token', clientIdentifier: 'client-id');

Map<String, Object?> _metadata({
  String ratingKey = 'plex-movie-1',
  String type = 'movie',
  String title = 'Inception',
  String imdb = 'tt1375666',
  int tmdb = 27205,
}) => {
  'ratingKey': ratingKey,
  'guid': 'plex://$type/$ratingKey',
  'type': type,
  'title': title,
  'year': 2010,
  'summary': 'A dream within a dream.',
  'duration': 8880000,
  'rating': 8.7,
  'contentRating': 'PG-13',
  'thumb': 'https://metadata-static.plex.tv/poster.jpg',
  'art': 'https://metadata-static.plex.tv/art.jpg',
  'Genre': [
    {'tag': 'Science Fiction'},
  ],
  'Guid': [
    {'id': 'imdb://$imdb'},
    {'id': 'tmdb://$tmdb'},
  ],
};

/// An entry of the `availabilityPlatforms` shelf: a streaming service, with a
/// logo and a hub of its own instead of a kind and a rating key.
Map<String, Object?> _platform(String title, {String? id}) => {
  'id': id ?? title.toLowerCase(),
  'title': title,
  'key': '/library/platforms/${id ?? title.toLowerCase()}',
  'tagType': 321,
  'thumb': 'https://provider-static.plex.tv/discover/logos/p/${id ?? title.toLowerCase()}.png',
};

/// Discover answers `/hubs/sections/<section>` with placeholders only — the
/// shelf identity, never its items.
Map<String, Object?> _placeholderHub(String id, String title, {String type = 'mixed', String? style}) => {
  'hubIdentifier': id,
  'key': '/hubs/sections/home/${id.split('.').last}?source=home',
  'title': title,
  'type': type,
  'style': ?style,
  'placeholder': true,
  'size': 0,
  'more': true,
};

void main() {
  group('PlexCatalogSource', () {
    test('watchlist uses offset paging and maps Plex metadata', () async {
      late http.Request captured;
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            captured = request;
            return jsonResponse({
              'MediaContainer': {
                'offset': 25,
                'size': 1,
                'totalSize': 27,
                'Metadata': [_metadata()],
              },
            });
          }),
        ),
      );
      addTearDown(source.dispose);

      final page = await source.fetchRow(CatalogRowId.watchlist, page: 2, limit: 25);

      expect(captured.method, 'GET');
      expect(captured.url.path, '/library/sections/watchlist/all');
      expect(captured.url.queryParameters['X-Plex-Container-Start'], '25');
      expect(captured.url.queryParameters['X-Plex-Container-Size'], '25');
      expect(captured.url.queryParameters['includeGuids'], '1');
      expect(captured.url.queryParameters['includeMeta'], '1');
      expect(captured.headers['X-Plex-Token'], 'profile-token');
      expect(captured.headers['X-Plex-Client-Identifier'], 'client-id');
      expect(page.hasMore, isTrue);
      expect(page.totalResults, 27);

      final item = page.items.single;
      expect(item.source, CatalogSourceId.plex);
      expect(item.kind, MediaKind.movie);
      expect(item.title, 'Inception');
      expect(item.runtimeMinutes, 148);
      expect(item.ids.plex, 'plex-movie-1');
      expect(item.ids.imdb, 'tt1375666');
      expect(item.ids.tmdb, 27205);
      expect(item.genres, ['Science Fiction']);
    });

    test('asks the watchlist for the account play state and reads both shapes it comes in', () async {
      late http.Request captured;
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            captured = request;
            return jsonResponse({
              'MediaContainer': {
                'totalSize': 4,
                'Metadata': [
                  // On the entry itself.
                  {..._metadata(ratingKey: 'seen', title: 'Seen', imdb: 'tt1', tmdb: 1), 'viewCount': 1},
                  {..._metadata(ratingKey: 'unseen', title: 'Unseen', imdb: 'tt2', tmdb: 2), 'viewCount': 0},
                  // Under a UserState object, and counted per episode.
                  {
                    ..._metadata(ratingKey: 'show', type: 'show', title: 'Show', imdb: 'tt3', tmdb: 3),
                    'UserState': {'leafCount': 10, 'viewedLeafCount': 10},
                  },
                  {
                    ..._metadata(ratingKey: 'half', type: 'show', title: 'Half', imdb: 'tt4', tmdb: 4),
                    'UserState': {'leafCount': 10, 'viewedLeafCount': 4},
                  },
                ],
              },
            });
          }),
        ),
      );
      addTearDown(source.dispose);

      final page = await source.fetchRow(CatalogRowId.watchlist);
      final watched = {for (final item in page.items) item.title: item.isWatched};

      expect(captured.url.queryParameters['includeUserState'], '1');
      expect(watched, {'Seen': true, 'Unseen': false, 'Show': true, 'Half': false});
      expect(page.items.first.toMediaItem().isWatched, isTrue, reason: 'the grids read the MediaItem, not the entry');
    });

    test('a watchlist entry without play state stays unanswered rather than unwatched', () async {
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient(
            (_) async => jsonResponse({
              'MediaContainer': {
                'totalSize': 1,
                'Metadata': [_metadata()],
              },
            }),
          ),
        ),
      );
      addTearDown(source.dispose);

      final item = (await source.fetchRow(CatalogRowId.watchlist)).items.single;

      expect(item.isWatched, isNull);
      expect(item.toMediaItem().isWatched, isFalse, reason: 'unknown reads as unwatched, and is never called watched');
    });

    test('maps every attributed score and leaves absent optional metadata null', () async {
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient(
            (_) async => jsonResponse({
              'MediaContainer': {
                'totalSize': 2,
                'Metadata': [
                  {
                    ..._metadata(),
                    'rating': 9.4,
                    'ratingImage': 'rottentomatoes://image.rating.ripe',
                    'audienceRating': 9.7,
                    'audienceRatingImage': 'rottentomatoes://image.rating.upright',
                    'imdbRatingCount': 250858,
                    'Rating': [
                      {'image': 'imdb://image.rating', 'type': 'audience', 'value': 8.5},
                      {'image': 'rottentomatoes://image.rating.ripe', 'type': 'critic', 'value': 94},
                      {'image': 'rottentomatoes://image.rating.upright', 'type': 'audience', 'value': 9.7},
                      {'image': 'themoviedb://image.rating', 'type': 'audience', 'value': 8},
                    ],
                    'originallyAvailableAt': '2010-07-16',
                    'originalTitle': 'Origine',
                    'tagline': 'Your mind is the scene of the crime.',
                    'banner': 'https://metadata-static.plex.tv/banner.jpg',
                    'budget': 160000000,
                    'revenue': '839000000',
                  },
                  {
                    // Distinct external ids: the mapper dedupes on identity,
                    // and reusing the default imdb/tmdb would collapse this
                    // row into the scored one above.
                    ..._metadata(ratingKey: 'plex-movie-2', title: 'No Score', imdb: 'tt0000002', tmdb: 2),
                    'rating': null,
                  },
                ],
              },
            }),
          ),
        ),
      );
      addTearDown(source.dispose);

      final page = await source.fetchRow(CatalogRowId.watchlist);
      final item = page.items.first;
      final ratings = {for (final rating in item.ratings!) rating.source: (value: rating.value, votes: rating.votes)};

      expect(item.rating, 9.4);
      expect(ratings, {
        'rottenTomatoesCritic': (value: 9.4, votes: null),
        'rottenTomatoesAudience': (value: 9.7, votes: null),
        'imdb': (value: 8.5, votes: 250858),
        'tmdb': (value: 8.0, votes: null),
      });
      expect(item.releaseDate, DateTime(2010, 7, 16));
      expect(item.originalTitle, 'Origine');
      expect(item.tagline, 'Your mind is the scene of the crime.');
      expect(item.bannerUrl, 'https://metadata-static.plex.tv/banner.jpg');
      expect(item.budget, 160000000);
      expect(item.revenue, 839000000);

      final absent = page.items.last;
      expect(absent.rating, isNull);
      expect(absent.ratings, isNull);
      expect(absent.releaseDate, isNull);
      expect(absent.posterVariants, isNull);
      expect(absent.backdropVariants, isNull);
    });

    test('home shelves are hydrated from their placeholder keys', () async {
      final requests = <http.Request>[];
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            requests.add(request);
            switch (request.url.path) {
              case '/hubs/sections/home':
                // Discover answers the section listing with placeholders: no
                // hub carries Metadata, so each shelf needs its own request.
                return jsonResponse({
                  'MediaContainer': {
                    'Hub': [
                      _placeholderHub('home.trending-plex', 'Trending on Plex', style: 'shelf'),
                      _placeholderHub('home.genres', 'Browse by Genre', type: 'directory'),
                      _placeholderHub('home.new-trailers', 'New Trailers', type: 'clip'),
                      _placeholderHub('home.people', 'People'),
                      // Typed a directory, because a shelf of services is a
                      // row of destinations — and dropped for that reason
                      // until the style was allowed to outrank the type.
                      _placeholderHub(
                        'home.platforms',
                        'Available On',
                        type: 'directory',
                        style: 'availabilityPlatforms',
                      ),
                      _placeholderHub('home.chris-nolan', 'The Films of Sir Christopher Nolan'),
                    ],
                  },
                });
              case '/hubs/sections/home/trending-plex':
                return jsonResponse({
                  'MediaContainer': {
                    'Metadata': [
                      _metadata(),
                      {
                        ..._metadata(ratingKey: 'plex-show-1', type: 'show', title: 'Severance'),
                        'isContinuingSeries': true,
                        'nextEpisodeOriginallyAvailableAt': '2026-08-04',
                      },
                      _metadata(ratingKey: 'plex-movie-2', title: 'Interstellar'),
                    ],
                  },
                });
              case '/hubs/sections/home/people':
                return jsonResponse({
                  'MediaContainer': {
                    'Metadata': [
                      {'ratingKey': 'person-1', 'type': 'person', 'title': 'A Person'},
                    ],
                  },
                });
              case '/hubs/sections/home/platforms':
                // Under Directory, which is where Discover files entries that
                // are destinations rather than titles — read only as Metadata
                // the shelf came back empty.
                return jsonResponse({
                  'MediaContainer': {
                    'Directory': [
                      _platform('Netflix'),
                      _platform('Disney+', id: 'disney-plus'),
                      // No logo and no hub of its own: nothing to draw, and
                      // nowhere to go.
                      {'title': 'Nowhere'},
                    ],
                  },
                });
              case '/hubs/sections/home/chris-nolan':
                return jsonResponse({
                  'MediaContainer': {
                    'Metadata': [_metadata(ratingKey: 'plex-movie-3', title: 'The Prestige')],
                  },
                });
            }
            return jsonResponse({'error': 'unexpected'}, status: 500);
          }),
        ),
      );
      addTearDown(source.dispose);

      final hubs = await source.fetchHubs(limit: 2);

      // Browse-category and trailer shelves cannot produce a catalog item, so
      // they never cost a hydration request.
      expect(requests.map((request) => request.url.path), [
        '/hubs/sections/home',
        '/hubs/sections/home/trending-plex',
        // A browse shelf is hydrated too now: its entries are destinations,
        // and destinations are tiles.
        '/hubs/sections/home/genres',
        '/hubs/sections/home/people',
        '/hubs/sections/home/platforms',
        '/hubs/sections/home/chris-nolan',
      ]);
      final shelfRequest = requests.singleWhere((request) => request.url.path == '/hubs/sections/home/trending-plex');
      final platformRequest = requests.singleWhere((request) => request.url.path == '/hubs/sections/home/platforms');
      expect(shelfRequest.url.queryParameters, containsPair('limit', '3'));
      // A shelf of destinations is asked for in full instead of for the
      // caller's handful: it has no "View All" anywhere in the app, so what
      // the container size cuts is gone rather than a page away.
      final genreRequest = requests.singleWhere((request) => request.url.path == '/hubs/sections/home/genres');
      expect(genreRequest.url.queryParameters, containsPair('limit', '61'));
      expect(platformRequest.url.queryParameters, containsPair('limit', '61'));
      expect(shelfRequest.url.queryParameters, containsPair('includeMeta', '1'));
      expect(shelfRequest.url.queryParameters, containsPair('includeUserState', '1'));
      expect(shelfRequest.url.queryParameters, containsPair('source', 'home'));
      expect(shelfRequest.url.queryParameters, containsPair('excludeElements', 'Media,Image'));
      expect(platformRequest.url.queryParameters, containsPair('excludeElements', 'Media,Image'));

      // The people-only shelf maps to nothing and drops out, and so does the
      // platform shelf — its entries are services, and they leave as tiles
      // rather than as a row of posters. Explicit styles survive, while an
      // absent hint remains null instead of becoming shelf.
      expect(hubs.map((hub) => hub.id), ['home.trending-plex', 'home.chris-nolan']);
      expect(hubs.map((hub) => hub.style), [CatalogHubStyle.shelf, null]);
      expect(source.tileShelves.single.tiles.map((tile) => tile.title), ['Netflix', 'Disney+']);
      expect(source.tileShelves.single.isPlatform, isTrue, reason: "Discover's own hub style says so");
      expect(hubs.first.title, 'Trending on Plex');
      expect(hubs.first.page.items.map((item) => item.title), ['Inception', 'Severance']);
      expect(hubs.first.page.hasMore, isTrue);
      final show = hubs.first.page.items.last;
      expect(show.airStatus, CatalogAirStatus.airing);
      expect(show.nextEpisode?.airsAt, DateTime(2026, 8, 4));
      expect(show.endDate, isNull);

      expect(hubs.last.page.items.single.title, 'The Prestige');
      expect(hubs.last.page.hasMore, isFalse);
    });

    test('a platform tile opens the service\'s own shelves', () async {
      // The point of keeping the shelf: each service carries a hub key, and
      // that key is what a tap follows.
      final paths = <String>[];
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            paths.add(request.url.path);
            switch (request.url.path) {
              case '/hubs/sections/home':
                return jsonResponse({
                  'MediaContainer': {
                    'Hub': [_placeholderHub('home.platforms', 'Available On', style: 'availabilityPlatforms')],
                  },
                });
              case '/hubs/sections/home/platforms':
                return jsonResponse({
                  'MediaContainer': {
                    'Metadata': [_platform('Netflix')],
                  },
                });
              case '/library/platforms/netflix':
                // A service's page is shelves, and empty ones at that:
                // Discover answers a section with placeholders and expects
                // each shelf to be fetched by its own key.
                return jsonResponse({
                  'MediaContainer': {
                    'Hub': [
                      {'title': 'Popular on Netflix', 'key': '/library/platforms/netflix/popular', 'size': 0},
                      {'title': 'New', 'key': '/library/platforms/netflix/new', 'size': 0},
                    ],
                  },
                });
              case '/library/platforms/netflix/popular':
                return jsonResponse({
                  'MediaContainer': {
                    'Metadata': [_metadata(title: 'Inception')],
                  },
                });
              case '/library/platforms/netflix/new':
                return jsonResponse({
                  'MediaContainer': {
                    // Ids of its own: the fixture's defaults are shared, and
                    // two titles under one identity are one title.
                    'Metadata': [
                      _metadata(ratingKey: 'plex-movie-9', title: 'The Prestige', imdb: 'tt0482571', tmdb: 1124),
                    ],
                  },
                });
            }
            return jsonResponse({'error': 'unexpected'}, status: 500);
          }),
        ),
      );
      addTearDown(source.dispose);

      expect(await source.fetchHubs(), isEmpty, reason: 'services are tiles, never a row of posters');

      final tile = source.tileShelves.single.tiles.single;
      expect(tile.id, 'netflix');
      expect(tile.sectionKey, '/library/platforms/netflix');
      expect(tile.imageUrl, 'https://provider-static.plex.tv/discover/logos/p/netflix.png');

      // The service's page as Plex files it: its own shelves, each named and
      // each with its titles — not one grid of everything it carries.
      final shelves = await source.fetchSectionHubs(tile.sectionKey);

      expect(shelves.map((shelf) => shelf.title), ['Popular on Netflix', 'New']);
      expect(shelves.first.page.items.map((item) => item.title), ['Inception']);
      expect(shelves.last.page.items.map((item) => item.title), ['The Prestige']);
      expect(paths, contains('/library/platforms/netflix'));
      expect(paths, contains('/library/platforms/netflix/popular'), reason: 'a placeholder shelf is followed');

      // And a row's View All follows that shelf's own key.
      final viewAll = await source.fetchHub(shelves.first.id);

      expect(viewAll.items.map((item) => item.title), ['Inception']);
    });

    test("a service's page is read the way Discover really answers it", () async {
      // The Disney+ payload, field for field: fourteen placeholder shelves,
      // every one sized 0, one of them trailers and one a browse category.
      // Written from the live answer rather than from what seemed likely.
      const shelves = [
        ('Trending on Disney+', 'mixed', '/library/platforms/disney-plus/trend'),
        ('Exclusively on Disney+', 'mixed', '/library/platforms/disney-plus/exclusives'),
        ('Trending Trailers', 'clip', '/library/platforms/disney-plus/trending-trailers'),
        ('Popular Genres on Disney+', 'directory', '/library/platforms/disney-plus/popular-genres'),
        ('Surprise Me', 'mixed', '/library/platforms/disney-plus/random'),
      ];
      final asked = <String>[];
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            asked.add(request.url.path);
            if (request.url.path == '/library/platforms/disney-plus') {
              return jsonResponse({
                'MediaContainer': {
                  'librarySectionID': 1,
                  'title': 'Disney+',
                  'size': 14,
                  'Hub': [
                    for (final (title, type, key) in shelves) {'title': title, 'type': type, 'key': key, 'size': 0},
                  ],
                },
              });
            }
            for (final (title, type, key) in shelves) {
              if (request.url.path != key) continue;
              if (type == 'directory') {
                return jsonResponse({
                  'MediaContainer': {
                    'Directory': [
                      {'title': 'Drama', 'key': '/library/platforms/disney-plus/genre-drama'},
                    ],
                  },
                });
              }
              return jsonResponse({
                'MediaContainer': {
                  'Metadata': [_metadata(ratingKey: 'rk-$key', title: 'From $title', tmdb: key.hashCode)],
                },
              });
            }
            return jsonResponse({'error': 'unexpected'}, status: 500);
          }),
        ),
      );
      addTearDown(source.dispose);

      final hubs = await source.fetchSectionHubs('/library/platforms/disney-plus');

      expect(hubs.map((hub) => hub.title), [
        'Trending on Disney+',
        'Exclusively on Disney+',
        'Surprise Me',
      ], reason: 'the trailer shelf has no detail page to open, the browse shelf no titles');
      expect(hubs.first.page.items.single.title, 'From Trending on Disney+');
      expect(asked, contains('/library/platforms/disney-plus/trend'));
    });

    test('a browse shelf is not a shelf of services', () async {
      // Genres arrive with artwork of their own, so a shelf cannot be told by
      // its pictures — only Discover's hub style says which is which.
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            switch (request.url.path) {
              case '/hubs/sections/home':
                return jsonResponse({
                  'MediaContainer': {
                    'Hub': [_placeholderHub('home.genres', 'Nach Genre', type: 'directory')],
                  },
                });
              case '/hubs/sections/home/genres':
                return jsonResponse({
                  'MediaContainer': {
                    'Directory': [
                      {
                        'id': 'action',
                        'title': 'Action',
                        'key': '/library/genres/action',
                        'thumb': 'https://provider-static.plex.tv/genres/action.png',
                      },
                    ],
                  },
                });
            }
            return jsonResponse({'error': 'unexpected'}, status: 500);
          }),
        ),
      );
      addTearDown(source.dispose);

      await source.fetchHubs();

      final shelf = source.tileShelves.single;
      expect(shelf.isPlatform, isFalse, reason: 'artwork or not, this is a browse shelf');
      expect(shelf.title, 'Nach Genre', reason: "Discover's own heading, in the app's language");
      expect(shelf.tiles.single.sectionKey, '/library/genres/action');
    });

    test('the shelf headings are asked for in the app\'s language', () async {
      // Plex answers in the account's language otherwise, which is not the one
      // the app is being read in. Only the listing carries the header: the
      // shelves themselves are hydrated plainly, because a localized record
      // comes back with an empty summary where Plex has no translation.
      final localized = <String, bool>{};
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            localized[request.url.path] = request.headers.containsKey('Accept-Language');
            switch (request.url.path) {
              case '/hubs/sections/home':
                return jsonResponse({
                  'MediaContainer': {
                    'Hub': [_placeholderHub('home.trending-plex', 'Angesagt auf Plex', style: 'shelf')],
                  },
                });
              case '/hubs/sections/home/trending-plex':
                return jsonResponse({
                  'MediaContainer': {
                    'Metadata': [_metadata()],
                  },
                });
            }
            return jsonResponse({'error': 'unexpected'}, status: 500);
          }),
        ),
      );
      addTearDown(source.dispose);
      await LocaleSettings.setLocale(AppLocale.de);
      addTearDown(() => LocaleSettings.setLocale(AppLocale.en));

      final hubs = await source.fetchHubs();

      expect(hubs.single.title, 'Angesagt auf Plex');
      expect(localized['/hubs/sections/home'], isTrue, reason: 'the listing carries the headings');
      expect(localized['/hubs/sections/home/trending-plex'], isFalse, reason: 'the titles are asked for plainly');
    });

    PlexCatalogSource sourceWithPlatformEntries(List<Map<String, Object?>> entries) => PlexCatalogSource(
      PlexDiscoverClient(
        _session,
        httpClient: MockClient((request) async {
          switch (request.url.path) {
            case '/hubs/sections/home':
              return jsonResponse({
                'MediaContainer': {
                  'Hub': [_placeholderHub('home.platforms', 'Available On', style: 'availabilityPlatforms')],
                },
              });
            case '/hubs/sections/home/platforms':
              return jsonResponse({
                'MediaContainer': {'Directory': entries},
              });
          }
          return jsonResponse({'error': 'unexpected'}, status: 500);
        }),
      ),
    );

    test('an entry with nothing to open is left out', () async {
      // Discover's payload is undocumented and has changed shape before. An
      // unreadable one costs the row, never a screen of tiles leading nowhere.
      final source = sourceWithPlatformEntries([
        {'title': 'Disney+'},
        {'key': '/library/platforms/nameless'},
      ]);
      addTearDown(source.dispose);

      await source.fetchHubs();

      expect(source.tileShelves, isEmpty, reason: 'a shelf whose entries name nothing is no shelf');
    });

    test('a service without a logo is not a service', () async {
      // The shelf ends in Plex's own "Preferred Services" entry, which sets
      // which services the row shows and can only be answered in their web
      // client. It carries no logo, which is what tells it apart in any
      // language. A server-relative path counts as none: these tiles are
      // drawn without a server client, so it could not be resolved anyway.
      final source = sourceWithPlatformEntries([
        {
          'title': 'Netflix',
          'thumb': 'https://provider-static.plex.tv/netflix.png',
          'key': '/library/platforms/netflix',
        },
        {'title': 'Preferred Services', 'key': '/library/platforms/preferred'},
        {'title': 'Relative', 'thumb': '/library/relative.png', 'key': '/library/platforms/relative'},
      ]);
      addTearDown(source.dispose);

      await source.fetchHubs();

      final shelf = source.tileShelves.single;
      expect(shelf.tiles.map((tile) => tile.title), ['Netflix']);
      expect(shelf.isPlatform, isTrue);
    });

    test('source forwards the explicit hub Image opt-in', () async {
      final requests = <http.Request>[];
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.url.path == '/hubs/sections/home') {
              return jsonResponse({
                'MediaContainer': {
                  'Hub': [_placeholderHub('home.spotlight', 'Spotlight')],
                },
              });
            }
            return jsonResponse({
              'MediaContainer': {
                'Metadata': [_metadata()],
              },
            });
          }),
        ),
        includeImageVariants: true,
      );
      addTearDown(source.dispose);

      await source.fetchHubs();

      expect(requests.last.url.queryParameters, containsPair('includeUserState', '1'));
      expect(requests.last.url.queryParameters, containsPair('excludeElements', 'Media'));
    });

    test('View All takes a shelf in one request because Discover ignores offsets', () async {
      final requests = <http.Request>[];
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.url.path == '/hubs/sections/home') {
              return jsonResponse({
                'MediaContainer': {
                  'Hub': [_placeholderHub('home.trending-plex', 'Trending on Plex')],
                },
              });
            }
            return jsonResponse({
              'MediaContainer': {
                'Metadata': [
                  _metadata(),
                  _metadata(ratingKey: 'plex-movie-2', title: 'Interstellar', imdb: 'tt0816692', tmdb: 157336),
                ],
              },
            });
          }),
        ),
      );
      addTearDown(source.dispose);

      await source.fetchHubs(limit: 1);
      requests.clear();

      final page = await source.fetchHub('home.trending-plex', limit: 100);

      expect(requests.single.url.queryParameters, containsPair('limit', '100'));
      expect(requests.single.url.queryParameters.containsKey('X-Plex-Container-Start'), isFalse);
      expect(page.items.map((item) => item.title), ['Inception', 'Interstellar']);
      expect(page.hasMore, isFalse);

      // A second page would replay the same items, so it is never requested.
      requests.clear();
      final beyond = await source.fetchHub('home.trending-plex', page: 2, limit: 100);
      expect(beyond.items, isEmpty);
      expect(requests, isEmpty);
    });

    test('one failing shelf degrades, an entirely failing listing surfaces the error', () async {
      var failEverything = false;
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            if (request.url.path == '/hubs/sections/home') {
              return jsonResponse({
                'MediaContainer': {
                  'Hub': [
                    _placeholderHub('home.trending-plex', 'Trending on Plex'),
                    _placeholderHub('home.retired', 'Retired'),
                  ],
                },
              });
            }
            if (failEverything || request.url.path == '/hubs/sections/home/retired') {
              return jsonResponse({'error': 'gone'}, status: 500);
            }
            return jsonResponse({
              'MediaContainer': {
                'Metadata': [_metadata()],
              },
            });
          }),
        ),
      );
      addTearDown(source.dispose);

      final hubs = await source.fetchHubs(limit: 25);
      expect(hubs.map((hub) => hub.id), ['home.trending-plex']);

      failEverything = true;
      await expectLater(source.fetchHubs(limit: 25), throwsA(isA<PlexDiscoverException>()));
    });

    test('a vanished home shelf degrades to an empty page', () async {
      final requests = <http.Request>[];
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            requests.add(request);
            return jsonResponse({'error': 'unexpected'}, status: 500);
          }),
        ),
      );
      addTearDown(source.dispose);

      final page = await source.fetchHub('no-longer-present');

      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
      expect(requests, isEmpty);
    });

    test('search sends Plex universal-search values and deduplicates media', () async {
      late http.Request captured;
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            captured = request;
            return jsonResponse({
              'MediaContainer': {
                'SearchResults': [
                  {
                    'SearchResult': [
                      {'score': 0.91, 'Metadata': _metadata()},
                      {'score': 0.42, 'Metadata': _metadata()},
                      {
                        'Metadata': {'ratingKey': 'person-1', 'type': 'person', 'title': 'A Person'},
                      },
                    ],
                  },
                ],
              },
            });
          }),
        ),
      );
      addTearDown(source.dispose);

      final results = await source.search(' Inception ', limit: 12);

      expect(captured.url.path, '/library/search');
      expect(captured.url.queryParameters, containsPair('query', 'Inception'));
      expect(captured.url.queryParameters, containsPair('limit', '12'));
      expect(captured.url.queryParameters, containsPair('searchTypes', 'movies,tv'));
      expect(captured.url.queryParameters, containsPair('searchProviders', 'discover'));
      expect(results, hasLength(1));
      expect(results.single.ids.plex, 'plex-movie-1');
    });

    test('watchlist snapshot and mutation use the advertised action endpoint', () async {
      var watchlisted = true;
      final requests = <http.Request>[];
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.url.path == '/library/sections/watchlist/all') {
              return jsonResponse({
                'MediaContainer': {
                  'totalSize': watchlisted ? 1 : 0,
                  'Metadata': watchlisted ? [_metadata()] : <Object>[],
                },
              });
            }
            expect(request.method, 'PUT');
            expect(request.url.path, '/actions/removeFromWatchlist');
            expect(request.url.queryParameters['ratingKey'], 'plex-movie-1');
            watchlisted = false;
            return jsonResponse(const <String, Object?>{});
          }),
        ),
      );
      addTearDown(source.dispose);
      const ids = CatalogItemIds(plex: 'plex-movie-1', imdb: 'tt1375666');

      await source.ensureWatchlistLoaded();
      expect(source.isOnWatchlist(MediaKind.movie, ids), isTrue);

      await source.removeFromWatchlist(MediaKind.movie, ids);
      expect(source.isOnWatchlist(MediaKind.movie, ids), isFalse);
      expect(requests, hasLength(2));
      // The snapshot page must stay under Discover's container-size cap
      // (#1715: 500 was rejected outright).
      expect(requests.first.url.queryParameters['X-Plex-Container-Size'], '100');
    });

    test('watchlist snapshot keeps the first entry per identity and never unions discarded ids', () async {
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient(
            (request) async => jsonResponse({
              'MediaContainer': {
                'totalSize': 4,
                'Metadata': [
                  _metadata(),
                  // Same imdb identity, different Plex/tmdb ids: discarded,
                  // and its keys must not join the surviving entry's group.
                  _metadata(ratingKey: 'plex-movie-1-dupe', tmdb: 99999),
                  // Seasons are not Explore kinds.
                  _metadata(ratingKey: 'plex-season-1', type: 'season', imdb: 'tt5555555', tmdb: 5555),
                  // A missing title is rejected.
                  _metadata(ratingKey: 'plex-movie-2', title: '', imdb: 'tt6666666', tmdb: 6666),
                ],
              },
            }),
          ),
        ),
      );
      addTearDown(source.dispose);

      await source.ensureWatchlistLoaded();

      expect(source.isOnWatchlist(MediaKind.movie, const CatalogItemIds(plex: 'plex-movie-1')), isTrue);
      expect(source.isOnWatchlist(MediaKind.movie, const CatalogItemIds(imdb: 'tt1375666')), isTrue);
      expect(source.isOnWatchlist(MediaKind.movie, const CatalogItemIds(plex: 'plex-movie-1-dupe')), isFalse);
      expect(source.isOnWatchlist(MediaKind.movie, const CatalogItemIds(tmdb: 99999)), isFalse);
      expect(source.isOnWatchlist(MediaKind.show, const CatalogItemIds(imdb: 'tt5555555')), isFalse);
      expect(source.isOnWatchlist(MediaKind.movie, const CatalogItemIds(imdb: 'tt6666666')), isFalse);
    });

    test('an oversized watchlist page refetches as chunks when Discover rejects it', () async {
      final requests = <http.Request>[];
      final client = PlexDiscoverClient(
        _session,
        httpClient: MockClient((request) async {
          requests.add(request);
          final size = int.parse(request.url.queryParameters['X-Plex-Container-Size']!);
          if (size > 25) {
            return jsonResponse({
              'Error': {'message': 'Invalid value provided for x-plex-container-size!'},
            }, status: 400);
          }
          final start = int.parse(request.url.queryParameters['X-Plex-Container-Start']!);
          const total = 180;
          final count = (total - start).clamp(0, size);
          return jsonResponse({
            'MediaContainer': {
              'totalSize': total,
              'Metadata': [
                for (var i = 0; i < count; i++)
                  {'ratingKey': 'rk-${start + i}', 'type': 'movie', 'title': 'Movie ${start + i}'},
              ],
            },
          });
        }),
      );
      addTearDown(client.dispose);

      final page = await client.getWatchlist(page: 2, limit: 100);

      // The rejected request, then the same range in proven-size chunks:
      // the caller's offset math survives the cap drift.
      expect(
        requests.map(
          (request) => (
            request.url.queryParameters['X-Plex-Container-Start'],
            request.url.queryParameters['X-Plex-Container-Size'],
          ),
        ),
        [('100', '100'), ('100', '25'), ('125', '25'), ('150', '25'), ('175', '25')],
      );
      expect(page.items, hasLength(80));
      expect(page.items.first['ratingKey'], 'rk-100');
      expect(page.items.last['ratingKey'], 'rk-179');
      expect(page.hasMore, isFalse);
      expect(page.totalResults, 180);
    });

    test('other Discover rejections surface instead of chunking', () async {
      var requestCount = 0;
      final client = PlexDiscoverClient(
        _session,
        httpClient: MockClient((request) async {
          requestCount++;
          return jsonResponse({
            'Error': {'message': 'Maintenance'},
          }, status: 400);
        }),
      );
      addTearDown(client.dispose);

      await expectLater(client.getWatchlist(limit: 100), throwsA(isA<PlexDiscoverException>()));
      expect(requestCount, 1);
    });

    test('watchlist mutation resolves a missing Plex rating key from external ids', () async {
      final requests = <http.Request>[];
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.url.path == '/library/metadata/matches') {
              expect(request.url.queryParameters['guid'], 'imdb://tt1375666');

              expect(request.url.queryParameters['type'], '1');
              return jsonResponse({
                'MediaContainer': {
                  'Metadata': [_metadata()],
                },
              });
            }
            expect(request.method, 'PUT');
            expect(request.url.path, '/actions/addToWatchlist');
            expect(request.url.queryParameters['ratingKey'], 'plex-movie-1');
            return jsonResponse(const <String, Object?>{});
          }),
        ),
      );
      addTearDown(source.dispose);

      await source.addToWatchlist(MediaKind.movie, const CatalogItemIds(imdb: 'tt1375666'));

      expect(requests.map((request) => request.url.path), ['/library/metadata/matches', '/actions/addToWatchlist']);
    });
    test('an addition is remembered even when the list itself cannot be read', () async {
      // Plex Discover refuses the whole-list read often enough to be ordinary
      // (504). Without a record of our own the title came back unknown: no
      // mark on it, and the next press offered to add it again — while it was
      // already on the list, arriving there late.
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            if (request.url.path == '/library/sections/watchlist/all') {
              return jsonResponse(const <String, Object?>{}, status: 504);
            }
            if (request.url.path == '/library/metadata/matches') {
              return jsonResponse({
                'MediaContainer': {
                  'Metadata': [_metadata()],
                },
              });
            }
            expect(request.url.path, '/actions/addToWatchlist');
            return jsonResponse(const <String, Object?>{});
          }),
        ),
      );
      addTearDown(source.dispose);

      const ids = CatalogItemIds(imdb: 'tt1375666');
      await source.ensureWatchlistLoaded();
      expect(source.isOnWatchlist(MediaKind.movie, ids), isNull, reason: 'the list was refused, so nothing is known');

      await source.addToWatchlist(MediaKind.movie, ids);

      // What we did ourselves is known even when the list is not.
      expect(source.isOnWatchlist(MediaKind.movie, ids), isTrue);
    });

    test('our own record gives way once it has waited long enough', () async {
      // The record is a bet that the provider is slow, not that we are wrong.
      // Past the window the bet is off and the list decides — otherwise a
      // title removed on another device would stay marked all session.
      var now = DateTime(2026, 8, 30, 12);
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            if (request.url.path == '/library/sections/watchlist/all') {
              return jsonResponse({
                'MediaContainer': {
                  'size': 0,
                  'totalSize': 0,
                  // Still not showing it: the wait this record covers.
                  'Metadata': const <Object?>[],
                },
              });
            }
            if (request.url.path == '/library/metadata/matches') {
              return jsonResponse({
                'MediaContainer': {
                  'Metadata': [_metadata()],
                },
              });
            }
            return jsonResponse(const <String, Object?>{});
          }),
        ),
      );
      addTearDown(source.dispose);
      source.watchlistClock = () => now;

      const ids = CatalogItemIds(imdb: 'tt1375666');
      await source.addToWatchlist(MediaKind.movie, ids);
      expect(source.isOnWatchlist(MediaKind.movie, ids), isTrue);

      // A list that still does not show it, read inside the window: ours wins,
      // because this is exactly the wait it is meant to cover.
      await source.ensureWatchlistLoaded();
      expect(source.isOnWatchlist(MediaKind.movie, ids), isTrue);

      now = now.add(CatalogWatchlistMachinery.localMembershipWindow + const Duration(minutes: 1));

      expect(
        source.isOnWatchlist(MediaKind.movie, ids),
        isFalse,
        reason: 'past the window the provider has the last word',
      );
    });

    test('a watchlist mutation falls back to the search too, given the title', () async {
      // The gap this closes: the fallback existed, but the watchlist path
      // called the resolver without a title and so could never reach it. A
      // Seerr page carries a TMDB id and a title and nothing Plex indexed the
      // item under, which is exactly the case that failed.
      final paths = <String>[];
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            paths.add(request.url.path);
            if (request.url.path == '/library/metadata/matches') {
              // The id match knows nothing about it.
              return jsonResponse({
                'MediaContainer': {'Metadata': <Object?>[]},
              });
            }
            if (request.url.path == '/library/search') {
              expect(request.url.queryParameters['query'], 'The Matrix');
              return jsonResponse({
                'MediaContainer': {
                  'SearchResults': [
                    {
                      'SearchResult': [
                        {
                          'score': 0.9,
                          'Metadata': [_metadata()],
                        },
                      ],
                    },
                  ],
                },
              });
            }
            expect(request.method, 'PUT');
            expect(request.url.path, '/actions/addToWatchlist');
            expect(request.url.queryParameters['ratingKey'], 'plex-movie-1');
            return jsonResponse(const <String, Object?>{});
          }),
        ),
      );
      addTearDown(source.dispose);

      await source.addToWatchlist(MediaKind.movie, const CatalogItemIds(imdb: 'tt1375666'), title: 'The Matrix');

      expect(paths, contains('/library/search'));
      expect(paths.last, '/actions/addToWatchlist');
    });

    test('a title the id match misses is found through the search Discover does answer', () async {
      // The report this comes from: Discover's own pages list the series, but
      // its match endpoint answers nothing for the ids Plex's library holds.
      final requests = <String>[];
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            requests.add(request.url.path);
            if (request.url.path == '/library/metadata/matches') {
              return jsonResponse({
                'MediaContainer': {'Metadata': const []},
              });
            }
            expect(request.url.path, '/library/search');
            expect(request.url.queryParameters['query'], 'Reacher');
            return jsonResponse({
              'MediaContainer': {
                'SearchResults': [
                  {
                    'SearchResult': [
                      {
                        'score': 0.9,
                        'Metadata': [
                          _metadata(ratingKey: 'plex-show-9', type: 'show', title: 'Reacher', imdb: 'tt9288030'),
                        ],
                      },
                    ],
                  },
                ],
              },
            });
          }),
        ),
      );
      addTearDown(source.dispose);

      final resolved = await source.resolveItemIds(
        MediaKind.show,
        const ExternalIds(imdb: 'tt9288030'),
        title: 'Reacher',
      );

      expect(resolved?.plex, 'plex-show-9');
      expect(requests, ['/library/metadata/matches', '/library/search']);
    });

    test('a search row without guids is confirmed by reading its metadata', () async {
      // Discover's search rows do not reliably carry their Guid array even
      // when it is asked for, so the row alone cannot prove identity.
      final paths = <String>[];
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            paths.add(request.url.path);
            switch (request.url.path) {
              case '/library/metadata/matches':
                return jsonResponse({
                  'MediaContainer': {'Metadata': const []},
                });
              case '/library/search':
                return jsonResponse({
                  'MediaContainer': {
                    'SearchResults': [
                      {
                        'SearchResult': [
                          {
                            'Metadata': [
                              {'ratingKey': 'plex-show-9', 'type': 'show', 'title': 'Reacher'},
                            ],
                          },
                        ],
                      },
                    ],
                  },
                });
              default:
                expect(request.url.path, '/library/metadata/plex-show-9');
                return jsonResponse({
                  'MediaContainer': {
                    'Metadata': [
                      _metadata(ratingKey: 'plex-show-9', type: 'show', title: 'Reacher', imdb: 'tt9288030'),
                    ],
                  },
                });
            }
          }),
        ),
      );
      addTearDown(source.dispose);

      final resolved = await source.resolveItemIds(
        MediaKind.show,
        const ExternalIds(imdb: 'tt9288030'),
        title: 'Reacher',
      );

      expect(resolved?.plex, 'plex-show-9');
      expect(paths, ['/library/metadata/matches', '/library/search', '/library/metadata/plex-show-9']);
    });

    test('a search hit that carries other ids is not the same title', () async {
      // A title-only hit could be any remake; putting that on a watchlist is
      // worse than putting nothing there.
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            if (request.url.path == '/library/metadata/matches') {
              return jsonResponse({
                'MediaContainer': {'Metadata': const []},
              });
            }
            return jsonResponse({
              'MediaContainer': {
                'SearchResults': [
                  {
                    'SearchResult': [
                      {
                        'Metadata': [_metadata(ratingKey: 'other', title: 'Reacher', imdb: 'tt0000001', tmdb: 1)],
                      },
                    ],
                  },
                ],
              },
            });
          }),
        ),
      );
      addTearDown(source.dispose);

      expect(
        await source.resolveItemIds(MediaKind.show, const ExternalIds(imdb: 'tt9288030'), title: 'Reacher'),
        isNull,
      );
    });

    test('every id form is offered to the match endpoint, not just the first', () async {
      final guids = <String?>[];
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            guids.add(request.url.queryParameters['guid']);
            // Only the tvdb form is indexed for this title.
            if (request.url.queryParameters['guid'] == 'tvdb://12345') {
              return jsonResponse({
                'MediaContainer': {
                  'Metadata': [_metadata(ratingKey: 'plex-show-1', type: 'show')],
                },
              });
            }
            return jsonResponse({
              'MediaContainer': {'Metadata': const []},
            });
          }),
        ),
      );
      addTearDown(source.dispose);

      final resolved = await source.resolveItemIds(
        MediaKind.show,
        const ExternalIds(imdb: 'tt1', tmdb: 2, tvdb: 12345),
      );

      expect(resolved?.plex, 'plex-show-1');
      expect(guids, ['imdb://tt1', 'tmdb://2', 'tvdb://12345']);
    });

    test('external-id matching sends the Discover metadata type for the requested kind', () async {
      // Discover answers a guid lookup only when paired with the numeric
      // type; a bare guid returns an empty container for every item (#1873).
      final types = <String?>[];
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            expect(request.url.path, '/library/metadata/matches');
            types.add(request.url.queryParameters['type']);
            final type = switch (request.url.queryParameters['type']) {
              '1' => 'movie',
              '2' => 'show',
              _ => null,
            };
            if (type == null) return jsonResponse({'MediaContainer': const <String, Object?>{}});
            return jsonResponse({
              'MediaContainer': {
                'Metadata': [_metadata(ratingKey: 'plex-$type-1', type: type)],
              },
            });
          }),
        ),
      );
      addTearDown(source.dispose);

      const external = ExternalIds(tvdb: 73762);
      final show = await source.resolveItemIds(MediaKind.show, external);
      final movie = await source.resolveItemIds(MediaKind.movie, external);
      final episode = await source.resolveItemIds(MediaKind.episode, external);

      expect(show?.plex, 'plex-show-1');
      expect(movie?.plex, 'plex-movie-1');
      expect(episode, isNull, reason: 'only movies and shows have a Discover watchlist identity');
      expect(types, ['2', '1'], reason: 'unsupported kinds never hit the network');
    });
    test('external-id matching and fetchDetail return enriched item, cast, and related', () async {
      final requests = <http.Request>[];
      final metadataResponse = Completer<http.Response>();
      var relatedRequested = false;
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) {
            requests.add(request);
            switch (request.url.path) {
              case '/library/metadata/matches':
                expect(request.url.queryParameters['guid'], 'imdb://tt1375666');
                expect(request.url.queryParameters['type'], '2');
                return Future.value(
                  jsonResponse({
                    'MediaContainer': {
                      'Metadata': [_metadata(type: 'show')],
                    },
                  }),
                );
              case '/library/metadata/plex-movie-1':
                return metadataResponse.future;
              case '/library/metadata/plex-movie-1/related':
                relatedRequested = true;
                return Future.value(
                  jsonResponse({
                    'MediaContainer': {
                      'Hub': [
                        {
                          'Metadata': [_metadata(ratingKey: 'related-1', title: 'Interstellar')],
                        },
                      ],
                    },
                  }),
                );
            }
            return Future.value(jsonResponse({'error': 'unexpected'}, status: 500));
          }),
        ),
      );
      addTearDown(source.dispose);

      final resolved = await source.resolveItemIds(MediaKind.show, const ExternalIds(imdb: 'tt1375666'));
      expect(resolved?.plex, 'plex-movie-1');
      expect(resolved?.imdb, 'tt1375666');

      const item = CatalogItem(
        source: CatalogSourceId.plex,
        kind: MediaKind.show,
        title: 'Inception',
        overview: 'Row overview.',
        ids: CatalogItemIds(plex: 'plex-movie-1'),
      );
      final detailFuture = source.fetchDetail(item);
      await Future<void>.delayed(Duration.zero);
      expect(relatedRequested, isTrue, reason: 'metadata and related requests must start concurrently');

      metadataResponse.complete(
        jsonResponse({
          'MediaContainer': {
            'Metadata': [
              {
                ..._metadata(type: 'show'),
                'summary': 'Short summary.',
                'Summary': [
                  {'type': 'default', 'tag': 'A complete and much longer summary from detail metadata.'},
                ],
                'Role': [
                  {'tag': 'Ken Watanabe', 'role': 'Saito', 'thumb': 'https://images.plex.tv/ken.jpg'},
                ],
                'Director': [
                  {'tag': 'Christopher Nolan'},
                ],
                'Writer': [
                  {'tag': 'Jonathan Nolan'},
                ],
                'Producer': [
                  {'tag': 'Emma Thomas'},
                ],
                'Country': [
                  {'tag': 'United Kingdom'},
                  {'tag': 'United States of America'},
                ],
                'Studio': [
                  {'tag': 'Warner Bros.'},
                ],
                'Genre': [
                  {'tag': 'Science Fiction'},
                  {'tag': 'Thriller'},
                ],
                'Rating': [
                  {'image': 'imdb://image.rating', 'type': 'audience', 'value': 8.5},
                ],
                'imdbRatingCount': 250858,
                'CommonSenseMedia': [
                  {
                    'oneLiner': 'Complex themes and sustained peril.',
                    'AgeRating': [
                      {'age': 15, 'rating': 5, 'type': 'official'},
                    ],
                  },
                ],
                'originallyAvailableAt': '2010-07-16',
                'originalTitle': 'Origine',
                'tagline': 'Your mind is the scene of the crime.',
                'isContinuingSeries': false,
                'lastEpisodeOriginallyAvailableAt': '2010-12-01',
                'thumb': null,
                'art': null,
                'banner': null,
                'Image': [
                  {
                    'type': 'clearLogoWide',
                    'alt': 'Inception',
                    'url': 'https://metadata-static.plex.tv/inception-logo.png',
                  },
                  {
                    'type': 'coverPoster',
                    'alt': 'Inception',
                    'url': 'https://metadata-static.plex.tv/inception-poster.jpg',
                  },
                  {
                    'type': 'background',
                    'alt': 'Inception',
                    'url': 'https://metadata-static.plex.tv/inception-background.jpg',
                  },
                  {'type': 'banner', 'alt': 'Inception', 'url': 'https://assets.fanart.tv/inception-banner.jpg'},
                ],
              },
            ],
          },
        }),
      );
      final detail = await detailFuture;

      expect(detail.item.overview, 'A complete and much longer summary from detail metadata.');
      expect(detail.item.genres, ['Science Fiction', 'Thriller']);
      expect(detail.item.studios, ['Warner Bros.']);
      expect(detail.item.countries, ['GB', 'US']);
      expect(
        {for (final credit in detail.item.credits!) credit.role: credit.name},
        {
          CatalogCreditRole.director: 'Christopher Nolan',
          CatalogCreditRole.writer: 'Jonathan Nolan',
          CatalogCreditRole.producer: 'Emma Thomas',
        },
      );
      expect(detail.item.contentAdvisory, '15+ · Complex themes and sustained peril.');
      expect(detail.item.releaseDate, DateTime(2010, 7, 16));
      expect(detail.item.endDate, DateTime(2010, 12, 1));
      expect(detail.item.airStatus, CatalogAirStatus.ended);
      expect(detail.item.originalTitle, 'Origine');
      expect(detail.item.tagline, 'Your mind is the scene of the crime.');
      expect(detail.item.logoUrl, 'https://metadata-static.plex.tv/inception-logo.png');
      expect(detail.item.posterUrl, 'https://metadata-static.plex.tv/inception-poster.jpg');
      expect(detail.item.backdropUrl, 'https://metadata-static.plex.tv/inception-background.jpg');
      expect(detail.item.bannerUrl, 'https://assets.fanart.tv/inception-banner.jpg');
      expect(detail.item.posterVariants, isNull);
      expect(detail.item.backdropVariants, isNull);
      expect(
        detail.item.ratings,
        contains(
          isA<MediaRatingSource>()
              .having((rating) => rating.source, 'source', 'imdb')
              .having((rating) => rating.value, 'value', 8.5)
              .having((rating) => rating.votes, 'votes', 250858),
        ),
      );
      expect(detail.cast.single.name, 'Ken Watanabe');
      expect(detail.cast.single.secondary, 'Saito');
      expect(detail.related.single.title, 'Interstellar');
      expect(requests.where((request) => request.url.path == '/library/metadata/plex-movie-1'), hasLength(1));
      expect(requests.where((request) => request.url.path == '/library/metadata/plex-movie-1/related'), hasLength(1));
    });

    test('fetchDetail keeps enrichment and cast when the related call fails', () async {
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/related')) {
              return jsonResponse({'error': 'related unavailable'}, status: 503);
            }
            return jsonResponse({
              'MediaContainer': {
                'Metadata': [
                  {
                    ..._metadata(),
                    'summary': 'Detailed overview.',
                    'Director': [
                      {'tag': 'Christopher Nolan'},
                    ],
                    'Role': [
                      {'tag': 'Ken Watanabe', 'role': 'Saito'},
                    ],
                  },
                ],
              },
            });
          }),
        ),
      );
      addTearDown(source.dispose);
      const item = CatalogItem(
        source: CatalogSourceId.plex,
        kind: MediaKind.movie,
        title: 'Inception',
        ids: CatalogItemIds(plex: 'plex-movie-1'),
      );

      final detail = await source.fetchDetail(item);

      expect(detail.item.overview, 'Detailed overview.');
      expect(detail.item.credits?.single.name, 'Christopher Nolan');
      expect(detail.cast.single.name, 'Ken Watanabe');
      expect(detail.related, isEmpty);
    });

    test('fetchDetail without a Plex rating key returns the row without requests', () async {
      var requested = false;
      final source = PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((_) async {
            requested = true;
            return jsonResponse({'error': 'unexpected'}, status: 500);
          }),
        ),
      );
      addTearDown(source.dispose);
      const item = CatalogItem(
        source: CatalogSourceId.plex,
        kind: MediaKind.movie,
        title: 'Inception',
        ids: CatalogItemIds(imdb: 'tt1375666'),
      );

      final detail = await source.fetchDetail(item);

      expect(identical(detail.item, item), isTrue);
      expect(detail.cast, isEmpty);
      expect(detail.related, isEmpty);
      expect(requested, isFalse);
    });

    group('localized descriptions', () {
      // German is a deferred locale; setLocaleSync cannot load it.
      setUp(() async => LocaleSettings.setLocale(AppLocale.de));
      tearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));

      /// Serves a German summary only to a request that asked for one, which is
      /// how Discover behaves: it localizes when asked and otherwise answers
      /// English.
      PlexCatalogSource buildSource({String? germanSummary, List<String>? seenLanguages}) => PlexCatalogSource(
        PlexDiscoverClient(
          _session,
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/related')) return jsonResponse({'MediaContainer': {}});
            final language = request.headers['Accept-Language'];
            seenLanguages?.add(language ?? '');
            return jsonResponse({
              'MediaContainer': {
                'Metadata': [
                  {..._metadata(), if (language != null) 'summary': germanSummary ?? ''},
                ],
              },
            });
          }),
        ),
      );

      const item = CatalogItem(
        source: CatalogSourceId.plex,
        kind: MediaKind.movie,
        title: 'Inception',
        ids: CatalogItemIds(plex: 'plex-movie-1'),
      );

      test('a German description wins over the English one', () async {
        final languages = <String>[];
        final source = buildSource(germanSummary: 'Ein Traum im Traum.', seenLanguages: languages);
        addTearDown(source.dispose);

        final detail = await source.fetchDetail(item);

        expect(detail.item.overview, 'Ein Traum im Traum.');
        expect(languages, containsAll(<String>['', 'de']), reason: 'one plain record, one localized');
      });

      test('an untranslated title keeps its English description', () async {
        // Discover answers a localized request with an empty summary rather
        // than falling back, which is exactly why the plain record is fetched
        // too and stays the source of truth.
        final source = buildSource(germanSummary: null);
        addTearDown(source.dispose);

        final detail = await source.fetchDetail(item);

        expect(detail.item.overview, 'A dream within a dream.');
      });

      test('English asks once, because there is nothing to translate to', () async {
        LocaleSettings.setLocaleSync(AppLocale.en);
        final languages = <String>[];
        final source = buildSource(germanSummary: 'Nie gefragt.', seenLanguages: languages);
        addTearDown(source.dispose);

        final detail = await source.fetchDetail(item);

        expect(detail.item.overview, 'A dream within a dream.');
        expect(languages, ['']);
      });
    });

    test('Discover requests have a bounded duration', () async {
      final response = Completer<http.Response>();
      final client = PlexDiscoverClient(
        _session,
        httpClient: MockClient((request) => response.future),
        requestTimeout: Duration.zero,
      );
      addTearDown(client.dispose);

      await expectLater(client.getWatchlist(), throwsA(isA<TimeoutException>()));
    });
  });
}
