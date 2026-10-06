import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/providers/seerr_account_provider.dart';
import 'package:plezy/providers/trackers_provider.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/plex_discover_client.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/trackers/mdblist/mdblist_tracker.dart';
import 'package:plezy/services/trackers/tracker_account_store.dart';
import 'package:plezy/services/trackers/tracker_constants.dart';
import 'package:plezy/services/trackers/tracker_coordinator.dart';
import 'package:plezy/services/trackers/tracker_session.dart';
import 'package:plezy/utils/external_ids.dart';

import 'package:plezy/utils/fork_identity.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetSharedPreferencesForTest);

  test('profile hydration exposes Plex when Discover credentials are available', () async {
    var calls = 0;
    final provider = CatalogSourcesProvider(
      plexSessionSupplier: () async {
        calls++;
        return const PlexDiscoverSession(accessToken: 'profile-token', clientIdentifier: 'client-id');
      },
    );
    addTearDown(provider.dispose);

    await provider.onActiveProfileChanged('profile-1');

    expect(calls, 1);
    expect(provider.connectedSources.map((source) => source.id), [CatalogSourceId.plex]);
    expect(provider.activeSource?.displayName, 'Plex');
    expect(provider.watchlistCapableSource?.id, CatalogSourceId.plex);
  });

  test('profile hydration omits Plex when the active profile has no Plex identity', () async {
    final provider = CatalogSourcesProvider(plexSessionSupplier: () async => null);
    addTearDown(provider.dispose);

    await provider.onActiveProfileChanged('profile-1');

    expect(provider.connectedSources, isEmpty);
    expect(provider.hasAnySource, isFalse);
  });

  test('Plex session lookup failure does not abort profile hydration', () async {
    final provider = CatalogSourcesProvider(plexSessionSupplier: () async => throw StateError('vault unavailable'));
    addTearDown(provider.dispose);
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.onActiveProfileChanged('profile-1');

    expect(provider.connectedSources, isEmpty);
    expect(notifications, 1);
  });

  test('same-profile binding completion refreshes Plex connection state', () async {
    PlexDiscoverSession? session;
    var calls = 0;
    final provider = CatalogSourcesProvider(
      plexSessionSupplier: () async {
        calls++;
        return session;
      },
    );
    addTearDown(provider.dispose);

    await provider.onActiveProfileChanged('profile-1');
    await provider.onProfileBindingStateChanged(false);
    expect(calls, 1);
    expect(provider.connectedSources, isEmpty);

    await provider.onProfileBindingStateChanged(true);
    session = const PlexDiscoverSession(accessToken: 'connected', clientIdentifier: 'client-id');
    await provider.onProfileBindingStateChanged(false);
    expect(calls, 2);
    expect(provider.connectedSources.map((source) => source.id), [CatalogSourceId.plex]);

    await provider.onProfileBindingStateChanged(true);
    session = null;
    await provider.onProfileBindingStateChanged(false);
    expect(calls, 3);
    expect(provider.connectedSources, isEmpty);
  });
  test('tracker rebind exposes and removes the MDBList catalog source', () async {
    // MDBList is off in this fork; the binding machinery is what is tested.
    debugRemovedTrackersAvailable = true;
    addTearDown(() => debugRemovedTrackersAvailable = false);
    const userUuid = 'profile-mdblist';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await trackerAccountStore(TrackerService.mdblist).save(
      userUuid,
      TrackerSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: now + 3600,
        createdAt: now,
        username: 'alice',
      ),
    );
    BaseSharedPreferencesService.resetForTesting();

    final trackers = TrackersProvider();
    final seerr = SeerrAccountProvider();
    final sources = CatalogSourcesProvider(plexSessionSupplier: () async => null);
    addTearDown(() {
      sources.dispose();
      trackers.dispose();
      seerr.dispose();
      MdblistTracker.instance.rebindSession(null, onSessionInvalidated: () {});
    });

    await trackers.onActiveProfileChanged(userUuid);
    await TrackerCoordinator.instance.flushWriteQueue();
    sources.update(trackers, seerr);

    expect(sources.connectedSources.map((source) => source.id), [CatalogSourceId.mdblist]);
    expect(sources.activeSource?.displayName, 'MDBList');
    expect(sources.watchlistCapableSource?.id, CatalogSourceId.mdblist);

    await trackers.onActiveProfileChanged('empty-profile');
    await TrackerCoordinator.instance.flushWriteQueue();
    sources.update(trackers, seerr);

    expect(sources.connectedSources, isEmpty);
    expect(sources.hasAnySource, isFalse);
  });

  group('watchlist source binding', () {
    CatalogItem itemFrom(CatalogSourceId source) =>
        CatalogItem(source: source, kind: MediaKind.movie, title: 'Ein Film', ids: const CatalogItemIds(tmdb: 42));

    test('an item stays on its own list when its source keeps one', () {
      final trakt = _FakeWatchlistSource(CatalogSourceId.trakt);
      final plex = _FakeWatchlistSource(CatalogSourceId.plex);
      final provider = _FakeSourcesProvider([plex, trakt]);
      addTearDown(provider.dispose);

      // A Trakt card marks the Trakt list, never the first list that happens
      // to be connected.
      expect(provider.watchlistSourceFor(itemFrom(CatalogSourceId.trakt)), same(trakt));
    });

    test('an item from a source without a watchlist borrows one', () {
      final seerr = _FakeWatchlistSource(CatalogSourceId.seerr, supportsWatchlist: false);
      final plex = _FakeWatchlistSource(CatalogSourceId.plex);
      final provider = _FakeSourcesProvider([seerr, plex]);
      addTearDown(provider.dispose);

      // Seerr keeps no list of its own, so its pages would otherwise offer no
      // way at all to remember a title.
      expect(provider.watchlistSourceFor(itemFrom(CatalogSourceId.seerr)), same(plex));
    });

    test('with no list anywhere there is nothing to bind to', () {
      final seerr = _FakeWatchlistSource(CatalogSourceId.seerr, supportsWatchlist: false);
      final provider = _FakeSourcesProvider([seerr]);
      addTearDown(provider.dispose);

      expect(provider.watchlistSourceFor(itemFrom(CatalogSourceId.seerr)), isNull);
    });
  });

  group('a profile keeping its progress in Simkl', () {
    CatalogItem plexItem() => CatalogItem(
      source: CatalogSourceId.plex,
      kind: MediaKind.movie,
      title: 'Ein Film',
      ids: const CatalogItemIds(tmdb: 42),
    );

    Future<_FakeSourcesProvider> providerFor(String profile, {required List<String> simklLed}) async {
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.simklLedProfiles, simklLed);
      final provider = _FakeSourcesProvider([
        _FakeWatchlistSource(CatalogSourceId.simkl),
        _FakeWatchlistSource(CatalogSourceId.plex),
      ], plexSessionSupplier: () async => null);
      addTearDown(provider.dispose);
      await provider.onActiveProfileChanged(profile);
      return provider;
    }

    test('neither shows nor offers the Plex account\'s watchlist', () async {
      final provider = await providerFor('anna', simklLed: ['anna']);

      expect(provider.plexWatchlistSetAside, isTrue);
      expect(provider.watchlistCapableSources.map((source) => source.id), [CatalogSourceId.simkl]);
      expect(provider.watchlistCapableSource?.id, CatalogSourceId.simkl);
      expect(provider.watchlistSourceFor(plexItem())?.id, CatalogSourceId.simkl);
      expect(provider.rowsOf(provider.connectedSources.last), isNot(contains(CatalogRowId.watchlist)));
    });

    test('another profile keeps both', () async {
      final provider = await providerFor('ben', simklLed: ['anna']);

      expect(provider.plexWatchlistSetAside, isFalse);
      expect(provider.watchlistCapableSources.map((source) => source.id), [
        CatalogSourceId.simkl,
        CatalogSourceId.plex,
      ]);
      expect(provider.watchlistSourceFor(plexItem())?.id, CatalogSourceId.plex);
    });

    test('switching the choice changes the lists at once', () async {
      final provider = await providerFor('anna', simklLed: const []);
      var notified = 0;
      provider.addListener(() => notified++);

      await SettingsService.instance.write(SettingsService.simklLedProfiles, ['anna']);

      expect(notified, greaterThan(0));
      expect(provider.watchlistCapableSources.map((source) => source.id), [CatalogSourceId.simkl]);
    });
  });

  group('watchlist candidate cache', () {
    final item = testMediaItem(id: 'movie-1', serverId: 'server-1');

    test('resolves an item once per session and hands menus the cached result', () async {
      final source = _FakeWatchlistSource(CatalogSourceId.trakt);
      final provider = _FakeSourcesProvider([source]);
      addTearDown(provider.dispose);
      final client = _ExternalIdsClient(const ExternalIds(imdb: 'tt1'));

      expect(provider.cachedWatchlistCandidatesFor(item), isNull);
      final first = await provider.watchlistCandidatesFor(item, client: client);
      final second = await provider.watchlistCandidatesFor(item, client: client);

      expect(client.calls, 1);
      expect(first.single.source, same(source));
      expect(second, same(first));
      expect(provider.cachedWatchlistCandidatesFor(item), same(first));
    });

    test('concurrent loads for the same item coalesce into one resolution', () async {
      final provider = _FakeSourcesProvider([_FakeWatchlistSource(CatalogSourceId.trakt)]);
      addTearDown(provider.dispose);
      final gate = Completer<void>();
      final client = _ExternalIdsClient(const ExternalIds(imdb: 'tt1'), gate: gate);

      final first = provider.watchlistCandidatesFor(item, client: client);
      final second = provider.watchlistCandidatesFor(item, client: client);
      gate.complete();

      expect(await second, same(await first));
      expect(client.calls, 1);
    });

    test('a failed resolution is retried instead of cached', () async {
      final provider = _FakeSourcesProvider([_FakeWatchlistSource(CatalogSourceId.trakt)]);
      addTearDown(provider.dispose);
      final client = _ExternalIdsClient(const ExternalIds(imdb: 'tt1'), error: StateError('unreachable'));

      await expectLater(provider.watchlistCandidatesFor(item, client: client), throwsStateError);
      expect(provider.cachedWatchlistCandidatesFor(item), isNull);

      client.error = null;
      final candidates = await provider.watchlistCandidatesFor(item, client: client);
      expect(candidates, hasLength(1));
      expect(client.calls, 2);
    });

    test('an answer missing a source that failed to resolve is retried instead of cached', () async {
      final trakt = _FakeWatchlistSource(CatalogSourceId.trakt);
      final mal = _FakeWatchlistSource(CatalogSourceId.mal)..resolveError = StateError('mapping unavailable');
      final provider = _FakeSourcesProvider([trakt, mal]);
      addTearDown(provider.dispose);
      final client = _ExternalIdsClient(const ExternalIds(imdb: 'tt1'));

      final partial = await provider.watchlistCandidatesFor(item, client: client);
      expect(partial.map((candidate) => candidate.source.id), [CatalogSourceId.trakt]);
      expect(provider.cachedWatchlistCandidatesFor(item), isNull);

      mal.resolveError = null;
      final complete = await provider.watchlistCandidatesFor(item, client: client);
      expect(complete.map((candidate) => candidate.source.id), [CatalogSourceId.trakt, CatalogSourceId.mal]);
      expect(provider.cachedWatchlistCandidatesFor(item), same(complete));
    });

    test('a null client resolves to nothing without caching the miss', () async {
      final provider = _FakeSourcesProvider([_FakeWatchlistSource(CatalogSourceId.trakt)]);
      addTearDown(provider.dispose);

      expect(await provider.watchlistCandidatesFor(item, client: null), isEmpty);
      expect(provider.cachedWatchlistCandidatesFor(item), isNull);

      final candidates = await provider.watchlistCandidatesFor(
        item,
        client: _ExternalIdsClient(const ExternalIds(imdb: 'tt1')),
      );
      expect(candidates, hasLength(1));
    });

    test('a source rebind invalidates cached candidates', () async {
      PlexDiscoverSession? session = const PlexDiscoverSession(accessToken: 'a', clientIdentifier: 'client-id');
      final provider = _FakeSourcesProvider([
        _FakeWatchlistSource(CatalogSourceId.trakt),
      ], plexSessionSupplier: () async => session);
      addTearDown(provider.dispose);
      await provider.onActiveProfileChanged('profile-1');

      await provider.watchlistCandidatesFor(item, client: _ExternalIdsClient(const ExternalIds(imdb: 'tt1')));
      expect(provider.cachedWatchlistCandidatesFor(item), isNotNull);

      await provider.onProfileBindingStateChanged(true);
      session = const PlexDiscoverSession(accessToken: 'b', clientIdentifier: 'client-id');
      await provider.onProfileBindingStateChanged(false);

      expect(provider.cachedWatchlistCandidatesFor(item), isNull);
    });
  });
}

class _ExternalIdsClient implements MediaServerClient {
  _ExternalIdsClient(this.ids, {this.error, this.gate});

  final ExternalIds ids;
  Object? error;
  final Completer<void>? gate;
  int calls = 0;

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    calls++;
    await gate?.future;
    if (error != null) throw error!;
    return ids;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWatchlistSource implements CatalogSource {
  _FakeWatchlistSource(this.id, {this.supportsWatchlist = true});

  @override
  final CatalogSourceId id;

  /// Thrown by [resolveItemIds] while set — the provider being unreachable.
  Object? resolveError;

  @override
  final bool supportsWatchlist;

  @override
  List<CatalogRowId> get supportedRows => const [CatalogRowId.watchlist];

  @override
  Future<CatalogItemIds?> resolveItemIds(MediaKind kind, ExternalIds external, {String? title}) async {
    if (resolveError != null) throw resolveError!;
    return CatalogItemIds(imdb: external.imdb);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Overrides the bound-client source list so the cache can be exercised with
/// fake sources; the invalidation paths (Plex session rebinds) stay real.
class _FakeSourcesProvider extends CatalogSourcesProvider {
  _FakeSourcesProvider(this.sources, {super.plexSessionSupplier});

  final List<CatalogSource> sources;

  @override
  List<CatalogSource> get connectedSources => sources;
}
