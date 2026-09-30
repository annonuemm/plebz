import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/models/seerr/seerr_session.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/providers/explore_provider.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/catalog/seerr_catalog_source.dart';
import 'package:plezy/services/seerr/seerr_client.dart';
import 'package:plezy/models/seerr/seerr_brand.dart';

import '../test_helpers/media_items.dart';
import 'package:plezy/media/media_kind.dart';

/// Explore's three Seerr shelves: genres come from the instance, studios and
/// networks are the fixed lists Seerr's own website carries. Only the genre
/// shelf can offer both films and series, and only for the genres that exist
/// on both sides — the two lists are not the same list.
class _FakeSourcesProvider extends CatalogSourcesProvider {
  CatalogSource? _current;

  void setActive(CatalogSource? source) {
    _current = source;
    notifyListeners();
  }

  @override
  CatalogSource? get activeSource => _current;
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

SeerrCatalogSource _seerrSource() {
  final client = SeerrClient(
    SeerrSession(
      baseUrl: 'https://seerr.example.com',
      method: SeerrAuthMethod.local,
      identifier: 'alice',
      secret: 'hunter2',
      cookie: 'c',
      userId: 7,
      permissions: 2,
      displayName: 'Alice',
      instanceLabel: 'Seerr',
      createdAt: 0,
    ),
    onSessionInvalidated: () {},
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/genreslider/movie')) {
        return _json([
          // A film carries several genres, so the same backdrop is offered
          // for several of them.
          {
            'id': 28,
            'name': 'Action',
            'backdrops': <String>['/shared.jpg', '/action.jpg'],
          },
          {
            'id': 12,
            'name': 'Adventure',
            'backdrops': <String>['/shared.jpg', '/adventure.jpg'],
          },
          {
            'id': 99,
            'name': 'Documentary',
            'backdrops': <String>['/shared.jpg'],
          },
          {'id': 10770, 'name': 'TV Movie', 'backdrops': <String>[]},
        ]);
      }
      if (request.url.path.endsWith('/genreslider/tv')) {
        return _json([
          {'id': 10759, 'name': 'Action & Adventure', 'backdrops': <String>[]},
          {'id': 99, 'name': 'Documentary', 'backdrops': <String>[]},
        ]);
      }
      return _json({
        'page': 1,
        'totalPages': 1,
        'totalResults': 1,
        'results': [
          {'id': 1, 'mediaType': 'movie', 'title': 'Ein Film'},
        ],
      });
    }),
  );
  return SeerrCatalogSource(client);
}

Future<void> _pumpMicrotasks() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _FakeSourcesProvider sources;
  late ExploreProvider explore;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    sources = _FakeSourcesProvider();
    explore = ExploreProvider(sources);
    addTearDown(() {
      explore.dispose();
      sources.dispose();
    });
    sources.setActive(_seerrSource());
    await explore.load();
    await _pumpMicrotasks();
  });

  MediaHub? hubOfType(String type) {
    for (final rowHub in explore.rowHubs) {
      if (rowHub.hub.type == type) return rowHub.hub;
    }
    return null;
  }

  test('the three shelves are built, each marked so the rail can tell them apart', () {
    expect(hubOfType('genre'), isNotNull);
    expect(hubOfType('studio'), isNotNull, reason: 'Seerr serves no studio list; the app carries its own');
    expect(hubOfType('network'), isNotNull);
  });

  test('studio and network tiles carry the ids their endpoints need', () {
    final studios = hubOfType('studio')!;
    final networks = hubOfType('network')!;

    expect(studios.items.length, kSeerrStudios.length);
    expect(networks.items.length, kSeerrNetworks.length);
    expect(ExploreProvider.studioIdOf(studios.items.first), kSeerrStudios.first.id);
    expect(ExploreProvider.networkIdOf(networks.items.first), kSeerrNetworks.first.id);

    // A studio is not a network: an id read out of the wrong shelf would
    // send the tap to an endpoint that knows nothing about it.
    expect(ExploreProvider.networkIdOf(studios.items.first), isNull);
    expect(ExploreProvider.studioIdOf(networks.items.first), isNull);
    expect(ExploreProvider.genreIdOf(studios.items.first), isNull);
  });

  test('no two genre tiles show the same picture while another is free', () {
    final genres = hubOfType('genre')!;
    final art = {for (final item in genres.items) item.title: item.artPath};

    expect(art['Action'], contains('/shared.jpg'));
    // Adventure is offered the same picture first and has to take its own.
    expect(art['Adventure'], contains('/adventure.jpg'));
    // Documentary is offered nothing else, so it repeats rather than showing
    // an empty tile.
    expect(art['Documentary'], contains('/shared.jpg'));
    expect(art['TV Movie'], isNull);
  });

  test('a genre tile carries its series counterpart only where Seerr lists one', () {
    final genres = hubOfType('genre')!;
    final byName = {for (final item in genres.items) item.title: item};

    // Action is 28 for films and 10759 for series — matching on the id alone
    // would leave the series tab off a genre that has one.
    expect(ExploreProvider.genreIdOf(byName['Action']!), 28);
    expect(ExploreProvider.tvGenreIdOf(byName['Action']!), 10759);

    // Documentary is 99 on both sides.
    expect(ExploreProvider.tvGenreIdOf(byName['Documentary']!), 99);

    // TV Movie exists for films only: no series tab rather than an empty one.
    expect(ExploreProvider.genreIdOf(byName['TV Movie']!), 10770);
    expect(ExploreProvider.tvGenreIdOf(byName['TV Movie']!), isNull);
  });

  test('a brand tile is named for the spotlight, an ordinary title is not', () {
    // The spotlight stands in a real backdrop for these; everything else keeps
    // its own.
    final studio = ExploreProvider.brandItem(kSeerrStudios.first, ExploreProvider.studioIdPrefix);
    final network = ExploreProvider.brandItem(kSeerrNetworks.first, ExploreProvider.networkIdPrefix);

    expect(ExploreProvider.brandKeyOf(studio), 'studio:${kSeerrStudios.first.id}');
    expect(ExploreProvider.brandKeyOf(network), 'network:${kSeerrNetworks.first.id}');
    expect(ExploreProvider.brandKeyOf(testMediaItem(id: 'plain', kind: MediaKind.movie, title: 'Dune')), isNull);
  });

  group('shelf order', () {
    ExploreRowHub catalogRow(CatalogRowId row) => ExploreRowHub.catalogRow(
      row: row,
      hub: MediaHub(id: row.name, title: row.name, type: 'mixed', items: const [], size: 0),
    );
    ExploreRowHub providerHub(String id) => ExploreRowHub.providerHub(
      providerHubId: id,
      hub: MediaHub(id: id, title: id, type: 'network', items: const [], size: 0),
    );

    test('the streaming services sit directly under popular series', () {
      // Built with the other tile shelves at the end; a viewer reaches for a
      // service far more often than for a genre.
      final ordered = ExploreProvider.liftNetworksUnderPopularShows([
        catalogRow(CatalogRowId.popularMovies),
        catalogRow(CatalogRowId.popularShows),
        catalogRow(CatalogRowId.upcomingMovies),
        providerHub(ExploreProvider.genreHubId),
        providerHub(ExploreProvider.studioHubId),
        providerHub(ExploreProvider.networkHubId),
      ]);

      expect(ordered.map((entry) => entry.row?.name ?? entry.providerHubId), [
        CatalogRowId.popularMovies.name,
        CatalogRowId.popularShows.name,
        ExploreProvider.networkHubId,
        CatalogRowId.upcomingMovies.name,
        ExploreProvider.genreHubId,
        ExploreProvider.studioHubId,
      ]);
    });

    test('a list without one of the two is left alone', () {
      final withoutPopular = [providerHub(ExploreProvider.networkHubId), catalogRow(CatalogRowId.trending)];
      expect(ExploreProvider.liftNetworksUnderPopularShows(withoutPopular), same(withoutPopular));

      final withoutNetworks = [catalogRow(CatalogRowId.popularShows)];
      expect(ExploreProvider.liftNetworksUnderPopularShows(withoutNetworks), same(withoutNetworks));
    });

    test('a list already in that order is not rebuilt', () {
      final already = [catalogRow(CatalogRowId.popularShows), providerHub(ExploreProvider.networkHubId)];

      expect(ExploreProvider.liftNetworksUnderPopularShows(already), same(already));
    });
  });
}
