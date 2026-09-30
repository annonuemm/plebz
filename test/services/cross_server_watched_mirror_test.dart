import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/services/cross_server_watched_mirror.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/external_ids.dart';
import 'package:plezy/utils/watch_state_notifier.dart';

import '../test_helpers/prefs.dart';

/// A server holding named copies, answering the reverse lookup with whichever
/// of them matches the ids it is asked about.
class _FakeClient implements MediaServerClient {
  _FakeClient({
    required String id,
    this.items = const [],
    this.ids = const {},
    this.copies = const [],
    this.children = const {},
  }) : serverId = ServerId(id);

  @override
  final ServerId serverId;

  /// Items this server can hand back by id.
  final List<MediaItem> items;

  /// External ids per item id.
  final Map<String, ExternalIds> ids;

  /// What this server contributes to a reverse lookup.
  final List<MediaItem> copies;

  /// Children per parent id, for the season lookup.
  final Map<String, List<MediaItem>> children;

  final marked = <({String id, bool watched})>[];
  final childrenCalls = <String>[];
  var lookups = 0;

  @override
  Future<MediaItem?> fetchItem(String id) async {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => ids[itemId] ?? const ExternalIds();

  @override
  Future<List<MediaItem>> findByExternalIds(
    ExternalIds lookupIds, {
    required MediaKind kind,
    List<String> titles = const [],
    int? year,
    String? plexGuid,
    ExternalSeasonRef? season,
  }) async {
    lookups++;
    return copies;
  }

  @override
  Future<void> markWatched(MediaItem item) async => marked.add((id: item.id, watched: true));

  @override
  Future<void> markUnwatched(MediaItem item) async => marked.add((id: item.id, watched: false));

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async {
    childrenCalls.add(parentId);
    return children[parentId] ?? const [];
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _movie({
  required String id,
  required String serverId,
  String title = 'Dune',
  int? viewCount,
  MediaKind kind = MediaKind.movie,
}) => MediaItem.plex(id: id, kind: kind, title: title, year: 2021, serverId: serverId, viewCount: viewCount);

MediaItem _show({required String id, required String serverId, String title = 'Severance', int? viewCount}) =>
    MediaItem.plex(id: id, kind: MediaKind.show, title: title, year: 2022, serverId: serverId, viewCount: viewCount);

MediaItem _season({
  required String id,
  required String serverId,
  required String showId,
  required int number,
  int? viewCount,
}) => MediaItem.plex(
  id: id,
  kind: MediaKind.season,
  title: 'Season $number',
  index: number,
  parentId: showId,
  serverId: serverId,
  viewCount: viewCount,
);

WatchStateEvent _event(MediaItem item, {bool watched = true}) => WatchStateEvent(
  itemId: item.id,
  serverId: ServerId(item.serverId!),
  changeType: watched ? WatchStateChangeType.watched : WatchStateChangeType.unwatched,
  parentChain: const [],
  isNowWatched: watched,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dune = ExternalIds(imdb: 'tt1160419', tmdb: 438631);

  late SettingsService settings;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    settings = await SettingsService.getInstance();
  });

  /// Plex holds the watched original, Jellyfin an unwatched copy of the same
  /// film — the setup this whole feature exists for.
  ({
    MultiServerManager manager,
    CrossServerWatchedMirror mirror,
    _FakeClient plex,
    _FakeClient jellyfin,
    MediaItem watchedOnPlex,
  })
  twoServers({MediaKind kind = MediaKind.movie, ExternalIds sourceIds = dune}) {
    final onPlex = _movie(id: 'p1', serverId: 'plex', kind: kind, viewCount: 1);
    final onJellyfin = _movie(id: 'j1', serverId: 'jellyfin', kind: kind);
    final plex = _FakeClient(id: 'plex', items: [onPlex], ids: {'p1': sourceIds}, copies: [onPlex]);
    final jellyfin = _FakeClient(id: 'jellyfin', items: [onJellyfin], copies: [onJellyfin]);

    final manager = MultiServerManager();
    manager.debugRegisterClientForTesting(plex);
    manager.debugRegisterClientForTesting(jellyfin);
    addTearDown(manager.dispose);

    final mirror = CrossServerWatchedMirror(serverManager: manager, aggregation: DataAggregationService(manager));
    addTearDown(mirror.dispose);

    return (manager: manager, mirror: mirror, plex: plex, jellyfin: jellyfin, watchedOnPlex: onPlex);
  }

  test('does nothing until the setting is on', () async {
    final s = twoServers();

    await s.mirror.handleEvent(_event(s.watchedOnPlex));

    expect(s.jellyfin.marked, isEmpty, reason: 'writing to another server must be asked for');
    expect(s.plex.lookups, 0, reason: 'and it must not even go looking');
  });

  test('a film watched on one server is marked on the other', () async {
    await settings.write(SettingsService.mirrorWatchedAcrossServers, true);
    final s = twoServers();

    await s.mirror.handleEvent(_event(s.watchedOnPlex));

    expect(s.jellyfin.marked, [(id: 'j1', watched: true)]);
    // The copy the mark came from is already right; marking it again would be
    // a write for nothing.
    expect(s.plex.marked, isEmpty);
  });

  test('unmarking travels the same way', () async {
    await settings.write(SettingsService.mirrorWatchedAcrossServers, true);
    // Both sides watched: the Jellyfin copy is the one that has to be cleared.
    final onPlex = _movie(id: 'p1', serverId: 'plex', viewCount: 1);
    final onJellyfin = _movie(id: 'j1', serverId: 'jellyfin', viewCount: 1);
    final plex = _FakeClient(id: 'plex', items: [onPlex], ids: {'p1': dune}, copies: [onPlex]);
    final jellyfin = _FakeClient(id: 'jellyfin', copies: [onJellyfin]);
    final manager = MultiServerManager();
    manager.debugRegisterClientForTesting(plex);
    manager.debugRegisterClientForTesting(jellyfin);
    addTearDown(manager.dispose);
    final mirror = CrossServerWatchedMirror(serverManager: manager, aggregation: DataAggregationService(manager));
    addTearDown(mirror.dispose);

    await mirror.handleEvent(_event(onPlex, watched: false));

    expect(jellyfin.marked, [(id: 'j1', watched: false)]);
  });

  test('a second copy on the same server is marked too', () async {
    // A 4K section and an HD section hold the same film under two rating keys;
    // "every version" means both, not just the other server's.
    await settings.write(SettingsService.mirrorWatchedAcrossServers, true);
    final watched4k = _movie(id: 'p1', serverId: 'plex', viewCount: 1);
    final hdCopy = _movie(id: 'p2', serverId: 'plex');
    final plex = _FakeClient(id: 'plex', items: [watched4k], ids: {'p1': dune}, copies: [watched4k, hdCopy]);
    final manager = MultiServerManager();
    manager.debugRegisterClientForTesting(plex);
    addTearDown(manager.dispose);
    final mirror = CrossServerWatchedMirror(serverManager: manager, aggregation: DataAggregationService(manager));
    addTearDown(mirror.dispose);

    await mirror.handleEvent(_event(watched4k));

    expect(plex.marked, [(id: 'p2', watched: true)]);
  });

  test('a copy already in the right state is left alone', () async {
    await settings.write(SettingsService.mirrorWatchedAcrossServers, true);
    final onPlex = _movie(id: 'p1', serverId: 'plex', viewCount: 1);
    final alreadyWatched = _movie(id: 'j1', serverId: 'jellyfin', viewCount: 1);
    final plex = _FakeClient(id: 'plex', items: [onPlex], ids: {'p1': dune}, copies: [onPlex]);
    final jellyfin = _FakeClient(id: 'jellyfin', copies: [alreadyWatched]);
    final manager = MultiServerManager();
    manager.debugRegisterClientForTesting(plex);
    manager.debugRegisterClientForTesting(jellyfin);
    addTearDown(manager.dispose);
    final mirror = CrossServerWatchedMirror(serverManager: manager, aggregation: DataAggregationService(manager));
    addTearDown(mirror.dispose);

    await mirror.handleEvent(_event(onPlex));

    expect(jellyfin.marked, isEmpty);
  });

  test('episodes are out of scope', () async {
    await settings.write(SettingsService.mirrorWatchedAcrossServers, true);
    final s = twoServers(kind: MediaKind.episode);

    await s.mirror.handleEvent(_event(s.watchedOnPlex));

    expect(s.plex.lookups, 0, reason: 'an episode carries no id of its own to match on');
    expect(s.jellyfin.marked, isEmpty);
  });

  test('a film with no external id is never matched by title alone', () async {
    await settings.write(SettingsService.mirrorWatchedAcrossServers, true);
    final s = twoServers(sourceIds: const ExternalIds());

    await s.mirror.handleEvent(_event(s.watchedOnPlex));

    expect(s.plex.lookups, 0);
    expect(s.jellyfin.marked, isEmpty);
  });

  test('the echo of its own write does not start a second round', () async {
    // Writing a copy emits the same kind of event the mirror listens to. Left
    // unguarded that is a loop between the two servers.
    await settings.write(SettingsService.mirrorWatchedAcrossServers, true);
    final s = twoServers();

    await s.mirror.handleEvent(_event(s.watchedOnPlex));
    final lookupsAfterFirstPass = s.jellyfin.lookups;

    // What the Jellyfin write emitted, arriving back at the listener.
    await s.mirror.handleEvent(_event(_movie(id: 'j1', serverId: 'jellyfin', viewCount: 1)));

    expect(s.jellyfin.lookups, lookupsAfterFirstPass, reason: 'the echo must not fan out again');
    expect(s.jellyfin.marked, [(id: 'j1', watched: true)]);
  });

  test('a whole series is marked on the other server in one write', () async {
    // The point of stopping at series level: both backends mark the episodes
    // themselves, so a 60-episode show costs exactly what a film costs.
    await settings.write(SettingsService.mirrorWatchedAcrossServers, true);
    const severance = ExternalIds(imdb: 'tt11280740', tmdb: 95396);
    final onPlex = _show(id: 'p1', serverId: 'plex', viewCount: 1);
    final onJellyfin = _show(id: 'j1', serverId: 'jellyfin');
    final plex = _FakeClient(id: 'plex', items: [onPlex], ids: {'p1': severance}, copies: [onPlex]);
    final jellyfin = _FakeClient(id: 'jellyfin', copies: [onJellyfin]);
    final manager = MultiServerManager();
    manager.debugRegisterClientForTesting(plex);
    manager.debugRegisterClientForTesting(jellyfin);
    addTearDown(manager.dispose);
    final mirror = CrossServerWatchedMirror(serverManager: manager, aggregation: DataAggregationService(manager));
    addTearDown(mirror.dispose);

    await mirror.handleEvent(_event(onPlex));

    expect(jellyfin.marked, [(id: 'j1', watched: true)]);
    expect(jellyfin.childrenCalls, isEmpty, reason: 'no episode or season listing is owed for a whole series');
  });

  test('a season is matched through its show and its number', () async {
    await settings.write(SettingsService.mirrorWatchedAcrossServers, true);
    const severance = ExternalIds(imdb: 'tt11280740', tmdb: 95396);
    final showOnPlex = _show(id: 'p-show', serverId: 'plex');
    final seasonOnPlex = _season(id: 'p-s2', serverId: 'plex', showId: 'p-show', number: 2, viewCount: 1);
    final showOnJellyfin = _show(id: 'j-show', serverId: 'jellyfin');
    final plex = _FakeClient(
      id: 'plex',
      items: [showOnPlex, seasonOnPlex],
      ids: {'p-show': severance},
      copies: [showOnPlex],
    );
    final jellyfin = _FakeClient(
      id: 'jellyfin',
      copies: [showOnJellyfin],
      children: {
        'j-show': [
          _season(id: 'j-s1', serverId: 'jellyfin', showId: 'j-show', number: 1),
          _season(id: 'j-s2', serverId: 'jellyfin', showId: 'j-show', number: 2),
        ],
      },
    );
    final manager = MultiServerManager();
    manager.debugRegisterClientForTesting(plex);
    manager.debugRegisterClientForTesting(jellyfin);
    addTearDown(manager.dispose);
    final mirror = CrossServerWatchedMirror(serverManager: manager, aggregation: DataAggregationService(manager));
    addTearDown(mirror.dispose);

    await mirror.handleEvent(_event(seasonOnPlex));

    expect(jellyfin.marked, [(id: 'j-s2', watched: true)], reason: 'season 2 over there, not season 1');
    // The show the marked season already hangs off holds no second season 2,
    // so listing it would be a request for nothing.
    expect(plex.childrenCalls, isEmpty);
  });

  test('a season the other server does not have is simply not marked', () async {
    await settings.write(SettingsService.mirrorWatchedAcrossServers, true);
    const severance = ExternalIds(imdb: 'tt11280740', tmdb: 95396);
    final showOnPlex = _show(id: 'p-show', serverId: 'plex');
    final seasonOnPlex = _season(id: 'p-s3', serverId: 'plex', showId: 'p-show', number: 3, viewCount: 1);
    final showOnJellyfin = _show(id: 'j-show', serverId: 'jellyfin');
    final plex = _FakeClient(
      id: 'plex',
      items: [showOnPlex, seasonOnPlex],
      ids: {'p-show': severance},
      copies: [showOnPlex],
    );
    final jellyfin = _FakeClient(
      id: 'jellyfin',
      copies: [showOnJellyfin],
      children: {
        'j-show': [_season(id: 'j-s1', serverId: 'jellyfin', showId: 'j-show', number: 1)],
      },
    );
    final manager = MultiServerManager();
    manager.debugRegisterClientForTesting(plex);
    manager.debugRegisterClientForTesting(jellyfin);
    addTearDown(manager.dispose);
    final mirror = CrossServerWatchedMirror(serverManager: manager, aggregation: DataAggregationService(manager));
    addTearDown(mirror.dispose);

    await mirror.handleEvent(_event(seasonOnPlex));

    expect(jellyfin.marked, isEmpty);
  });

  test('a failing server does not take the others down with it', () async {
    await settings.write(SettingsService.mirrorWatchedAcrossServers, true);
    final onPlex = _movie(id: 'p1', serverId: 'plex', viewCount: 1);
    final plex = _FakeClient(id: 'plex', items: [onPlex], ids: {'p1': dune}, copies: [onPlex]);
    final broken = _ThrowingClient(
      id: 'jellyfin',
      copy: _movie(id: 'j1', serverId: 'jellyfin'),
    );
    final manager = MultiServerManager();
    manager.debugRegisterClientForTesting(plex);
    manager.debugRegisterClientForTesting(broken);
    addTearDown(manager.dispose);
    final mirror = CrossServerWatchedMirror(serverManager: manager, aggregation: DataAggregationService(manager));
    addTearDown(mirror.dispose);

    await expectLater(mirror.handleEvent(_event(onPlex)), completes);
  });
}

/// Answers the lookup but throws on the write, the way an unreachable server
/// behaves halfway through a pass.
class _ThrowingClient extends _FakeClient {
  _ThrowingClient({required super.id, required MediaItem copy}) : super(copies: [copy]);

  @override
  Future<void> markWatched(MediaItem item) async => throw StateError('server gone');
}
