import 'dart:async';

import 'package:flutter/material.dart' show ChangeNotifier, DateUtils, visibleForTesting;
import 'package:intl/intl.dart';

import '../../i18n/app_locale_utils.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../models/catalog/catalog_item.dart';
import '../../utils/app_logger.dart';
import '../catalog/plex_catalog_source.dart';
import '../plex_discover_client.dart';
import '../settings_service.dart';
import 'plex_community_client.dart';

/// One friend having watched a title, at a time.
class FriendWatch {
  const FriendWatch({required this.friend, required this.at, this.season, this.episode});

  final PlexFriend friend;
  final DateTime at;

  /// The episode, for a show.
  final int? season;
  final int? episode;
}

/// A title friends watched, with who and when — newest first.
class FriendTitle {
  const FriendTitle({required this.item, required this.watches});

  final CatalogItem item;
  final List<FriendWatch> watches;

  FriendWatch get latest => watches.first;

  /// The title as a tile: Explore's own item, carrying the latest watch for
  /// the picture of the friend on its poster ([friendWatchOf]).
  MediaItem toMediaItem({FriendWatch? watch}) {
    final shown = watch ?? latest;
    final media = item.toMediaItem();
    return media.copyWith(
      raw: {
        ...?media.raw,
        friendWatchRawKey: {
          'name': shown.friend.name,
          'initial': shown.friend.initial,
          'avatar': ?shown.friend.avatarUrl,
          'at': shown.at.millisecondsSinceEpoch,
        },
      },
    );
  }
}

/// Where a tile keeps the friend who watched it.
const friendWatchRawKey = 'plebz_friend_watch';

/// The friend a tile carries: name, initial, picture and when.
typedef FriendWatchMark = ({String name, String initial, String? avatarUrl, DateTime at});

FriendWatchMark? friendWatchOf(MediaItem item) {
  final data = item.raw?[friendWatchRawKey];
  if (data is! Map) return null;
  final name = data['name'];
  final at = data['at'];
  if (name is! String || at is! int) return null;
  final initial = data['initial'];
  final avatar = data['avatar'];
  return (
    name: name,
    initial: initial is String ? initial : '?',
    avatarUrl: avatar is String ? avatar : null,
    at: DateTime.fromMillisecondsSinceEpoch(at),
  );
}

/// "heute", "gestern", a weekday within the week, a date before that.
String friendWatchWhen(DateTime at, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final days = today.difference(DateUtils.dateOnly(at)).inDays;
  final locale = LocaleSettings.currentLocale.intlLocaleName;
  if (days <= 0) return t.friends.today;
  if (days == 1) return t.friends.yesterday;
  if (days < 7) return DateFormat.E(locale).format(at);
  return DateFormat.MMMd(locale).format(at);
}

/// What the Plex account's friends watched (Plebz): the home row, the line
/// on a detail page and the page under Explore all read it from here.
///
/// Bound to the active profile's Plex Discover session by the catalog
/// sources; without one — no Plex account, or a profile that keeps its own
/// progress on a shared account, whose friends are not the viewer's — it has
/// nothing to say and every surface stays away.
class FriendsActivity extends ChangeNotifier {
  FriendsActivity({PlexCommunityClient Function(PlexDiscoverSession session)? clientFor, DateTime Function()? now})
    : _clientFor = clientFor ?? PlexCommunityClient.new,
      _now = now ?? DateTime.now;

  static final FriendsActivity instance = FriendsActivity();

  final PlexCommunityClient Function(PlexDiscoverSession session) _clientFor;
  final DateTime Function() _now;

  /// How long the feed, the friend list and a title's watchers are kept.
  static const feedLifetime = Duration(minutes: 10);
  static const friendsLifetime = Duration(hours: 6);
  static const titleLifetime = Duration(minutes: 30);

  /// How many titles the feed is turned into at most.
  static const maxTitles = 40;

  PlexCommunityClient? _client;
  PlexCatalogSource? _source;
  bool _setAside = false;
  int _generation = 0;

  Map<String, PlexFriend>? _friends;
  DateTime? _friendsAt;
  Future<Map<String, PlexFriend>>? _friendsLoad;

  List<FriendTitle> _titles = const [];
  DateTime? _titlesAt;
  Future<void>? _feedLoad;

  final Map<String, ({DateTime at, List<FriendWatch> watches})> _watchers = {};
  final Map<String, Future<List<FriendWatch>>> _watcherLoads = {};
  final Map<String, CatalogItem?> _items = {};
  final Map<String, String?> _discoverIds = {};

  /// The catalog source bound last, so the provider that bound it can let go.
  PlexCatalogSource? get boundSource => _source;

  /// Whether this profile has friends to ask about at all.
  bool get isAvailable => _client != null && _source != null && !_setAside;

  /// Available, and the viewer has not switched it off.
  bool get isEnabled => isAvailable && (SettingsService.instanceOrNull?.read(PlebzPrefs.showFriendsActivity) ?? true);

  /// The titles friends watched lately, newest first. Empty until
  /// [ensureFeed] has run.
  List<FriendTitle> get titles => isEnabled ? _titles : const [];

  /// The friends who appear in [titles], in the order they last watched.
  List<PlexFriend> get activeFriends {
    final seen = <String>{};
    return [
      for (final title in titles)
        for (final watch in title.watches)
          if (seen.add(watch.friend.id)) watch.friend,
    ];
  }

  /// Follows the active profile's Plex Discover session.
  void bind({PlexDiscoverSession? session, PlexCatalogSource? source, bool setAside = false}) {
    final sameSession = _client?.session == session && session != null;
    if (sameSession && identical(_source, source) && _setAside == setAside) return;
    if (!sameSession) {
      _generation++;
      _client?.dispose();
      _client = session == null ? null : _clientFor(session);
      _friends = null;
      _friendsAt = null;
      _friendsLoad = null;
      _titles = const [];
      _titlesAt = null;
      _feedLoad = null;
      _watchers.clear();
      _watcherLoads.clear();
      _items.clear();
      _discoverIds.clear();
    }
    _source = source;
    _setAside = setAside;
    notifyListeners();
  }

  /// Load the feed unless a fresh one is at hand.
  Future<void> ensureFeed({bool force = false}) {
    if (!isEnabled) return Future.value();
    final at = _titlesAt;
    if (!force && at != null && _now().difference(at) < feedLifetime) return Future.value();
    return _feedLoad ??= _loadFeed().whenComplete(() => _feedLoad = null);
  }

  Future<void> _loadFeed() async {
    final client = _client;
    final source = _source;
    final generation = _generation;
    if (client == null || source == null) return;
    try {
      final friends = await _ensureFriends(client);
      if (generation != _generation) return;
      if (friends.isEmpty) {
        _titles = const [];
        _titlesAt = _now();
        notifyListeners();
        return;
      }
      final activity = await client.recentActivity();
      if (generation != _generation) return;
      final grouped = <String, List<FriendWatch>>{};
      for (final entry in activity) {
        final friend = friends[entry.userId];
        if (friend == null) continue;
        final watches = grouped.putIfAbsent(entry.titleId, () => []);
        // One line per friend and title: their latest watch of it.
        if (watches.any((watch) => watch.friend.id == friend.id)) continue;
        watches.add(FriendWatch(friend: friend, at: entry.at, season: entry.season, episode: entry.episode));
      }
      final ids = grouped.keys.take(maxTitles).toList();
      final items = await _resolveItems(source, ids, generation);
      if (generation != _generation) return;
      final titles = <FriendTitle>[];
      for (final id in ids) {
        final item = items[id];
        final watches = grouped[id]!..sort((a, b) => b.at.compareTo(a.at));
        if (item != null) titles.add(FriendTitle(item: item, watches: List.unmodifiable(watches)));
      }
      titles.sort((a, b) => b.latest.at.compareTo(a.latest.at));
      _titles = List.unmodifiable(titles);
      _titlesAt = _now();
      appLogger.d('Friends: ${titles.length} titles from ${friends.length} friends');
      notifyListeners();
    } catch (error) {
      appLogger.w('Friends: activity could not be read', error: error);
    }
  }

  Future<Map<String, PlexFriend>> _ensureFriends(PlexCommunityClient client) {
    final at = _friendsAt;
    final known = _friends;
    if (known != null && at != null && _now().difference(at) < friendsLifetime) return Future.value(known);
    final generation = _generation;
    return _friendsLoad ??= client
        .friends()
        .then((list) {
          final friends = {for (final friend in list) friend.id: friend};
          if (generation == _generation) {
            _friends = friends;
            _friendsAt = _now();
          }
          return friends;
        })
        .whenComplete(() => _friendsLoad = null);
  }

  /// Discover's records for [ids], four at a time, kept for the session.
  Future<Map<String, CatalogItem?>> _resolveItems(PlexCatalogSource source, List<String> ids, int generation) async {
    final missing = [
      for (final id in ids)
        if (!_items.containsKey(id)) id,
    ];
    for (var start = 0; start < missing.length; start += 4) {
      final batch = missing.skip(start).take(4);
      await Future.wait(
        batch.map((id) async {
          try {
            final item = await source.fetchItem(id);
            if (generation == _generation) _items[id] = item;
          } catch (error) {
            appLogger.d('Friends: title $id could not be read', error: error);
          }
        }),
      );
      if (generation != _generation) break;
    }
    return {for (final id in ids) id: _items[id]};
  }

  /// The friends who watched the title with Discover id [discoverId], each
  /// with their latest watch, newest first.
  Future<List<FriendWatch>> watchersOf(String discoverId) async {
    final client = _client;
    if (!isEnabled || client == null) return const [];
    final kept = _watchers[discoverId];
    if (kept != null && _now().difference(kept.at) < titleLifetime) return kept.watches;
    final generation = _generation;
    final load = _watcherLoads[discoverId] ??= () async {
      try {
        final friends = await _ensureFriends(client);
        if (friends.isEmpty) return const <FriendWatch>[];
        final activity = await client.activityFor(discoverId);
        final watches = <FriendWatch>[];
        for (final entry in activity) {
          final friend = friends[entry.userId];
          if (friend == null || watches.any((watch) => watch.friend.id == friend.id)) continue;
          watches.add(FriendWatch(friend: friend, at: entry.at, season: entry.season, episode: entry.episode));
        }
        watches.sort((a, b) => b.at.compareTo(a.at));
        if (generation == _generation) _watchers[discoverId] = (at: _now(), watches: List.unmodifiable(watches));
        return watches;
      } catch (error) {
        appLogger.d('Friends: watchers of $discoverId could not be read', error: error);
        return const <FriendWatch>[];
      } finally {
        _watcherLoads.removeWhere((key, _) => key == discoverId);
      }
    }();
    return load;
  }

  /// Discover's id for a library title: a Plex title names it in its guid;
  /// anything else is matched by its IMDb/TMDB/TVDB ids. Null when there is
  /// none — then no friend can be named for it.
  Future<String?> discoverIdOf(MediaItem item, {MediaServerClient? client}) async {
    final source = _source;
    if (!isEnabled || source == null) return null;
    final fromGuid = discoverIdFromGuid(item.guid);
    if (fromGuid != null) return fromGuid;
    final kind = item.kind;
    if (client == null || (kind != MediaKind.movie && kind != MediaKind.show)) return null;
    final key = item.globalKey;
    if (_discoverIds.containsKey(key)) return _discoverIds[key];
    try {
      final external = await client.fetchExternalIds(item.id);
      final ids = await source.resolveItemIds(kind, external, title: item.title);
      return _discoverIds[key] = ids?.plex;
    } catch (error) {
      appLogger.d('Friends: no Discover id for ${item.title}', error: error);
      return null;
    }
  }

  /// The id in a `plex://movie/<id>` or `plex://show/<id>` guid.
  static String? discoverIdFromGuid(String? guid) {
    final match = _titleGuid.firstMatch(guid ?? '');
    return match?.group(1);
  }

  static final _titleGuid = RegExp(r'^plex://(?:movie|show)/([A-Za-z0-9]{1,64})$');

  @visibleForTesting
  void debugReset() => bind();
}
