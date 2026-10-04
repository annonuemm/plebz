import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../media/catalog_item_ref.dart';
import '../../media/media_backend.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../models/catalog/catalog_item.dart';
import '../../profiles/profile.dart';
import '../../utils/app_logger.dart';
import '../base_shared_preferences_service.dart';
import 'catalog_source.dart';
import 'library_watchlist_candidates.dart';

/// A library title the watchlist provider does not know yet, kept by the app
/// itself.
@immutable
class LocalWatchlistEntry {
  const LocalWatchlistEntry({
    required this.serverId,
    required this.itemId,
    required this.backend,
    required this.kind,
    required this.title,
    this.year,
    required this.source,
    required this.addedAt,
    this.checkedAt,
    this.promotedAt,
    this.promotedIds,
  });

  final String serverId;
  final String itemId;
  final MediaBackend backend;
  final MediaKind kind;
  final String title;
  final int? year;

  /// The provider whose watchlist the title goes to once it knows it.
  final CatalogSourceId source;
  final DateTime addedAt;

  /// When the provider was last asked whether it knows the title now.
  final DateTime? checkedAt;

  /// Set once the title went to the provider. The entry stays a while after,
  /// standing in for it until the provider's own list shows it — Plex takes
  /// its time with an addition.
  final DateTime? promotedAt;
  final CatalogItemIds? promotedIds;

  String get key => LocalWatchlist.keyOf(serverId, itemId);

  bool get isPromoted => promotedAt != null;

  LocalWatchlistEntry _copy({DateTime? checkedAt, DateTime? promotedAt, CatalogItemIds? promotedIds}) =>
      LocalWatchlistEntry(
        serverId: serverId,
        itemId: itemId,
        backend: backend,
        kind: kind,
        title: title,
        year: year,
        source: source,
        addedAt: addedAt,
        checkedAt: checkedAt ?? this.checkedAt,
        promotedAt: promotedAt ?? this.promotedAt,
        promotedIds: promotedIds ?? this.promotedIds,
      );

  /// What the watchlist shows while the server cannot be asked for more.
  MediaItem toItem() =>
      MediaItem(id: itemId, backend: backend, kind: kind, title: title, year: year, serverId: serverId);

  Map<String, Object?> toJson() => {
    'serverId': serverId,
    'itemId': itemId,
    'backend': backend.id,
    'kind': kind.id,
    'title': title,
    'year': year,
    'source': source.name,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'checkedAt': checkedAt?.millisecondsSinceEpoch,
    'promotedAt': promotedAt?.millisecondsSinceEpoch,
    'promotedIds': promotedIds?.toJson(),
  };

  static LocalWatchlistEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final serverId = raw['serverId'];
    final itemId = raw['itemId'];
    final addedAt = raw['addedAt'];
    final source = CatalogSourceId.values.asNameMap()[raw['source']];
    if (serverId is! String || itemId is! String || addedAt is! int || source == null) return null;
    DateTime? time(Object? value) => value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;
    final promotedIds = raw['promotedIds'];
    return LocalWatchlistEntry(
      serverId: serverId,
      itemId: itemId,
      backend: MediaBackend.fromString(raw['backend'] as String?),
      kind: MediaKind.fromString(raw['kind'] as String?),
      title: raw['title'] as String? ?? '',
      year: raw['year'] as int?,
      source: source,
      addedAt: DateTime.fromMillisecondsSinceEpoch(addedAt),
      checkedAt: time(raw['checkedAt']),
      promotedAt: time(raw['promotedAt']),
      promotedIds: promotedIds is Map ? CatalogItemIds.fromJson(promotedIds.cast<String, Object?>()) : null,
    );
  }
}

/// The watchlist's fallback for library titles its provider does not know:
/// Plex Discover only takes titles from its own catalogue, and a new show can
/// be missing there for weeks. Rather than turn the press away, the app keeps
/// the title itself, per profile, on this device — and hands it to the
/// provider as soon as the provider knows it ([promoteDue]).
class LocalWatchlist extends ChangeNotifier {
  /// Profile-scoped; the settings backup carries it under this name.
  static const String baseKey = 'local_watchlist';

  /// How often one entry asks its provider again.
  static const Duration recheckInterval = Duration(hours: 1);

  /// How long a handed-over entry stands in for the provider's list.
  static const Duration promotedGrace = Duration(days: 1);

  /// Bound on provider lookups per watchlist load: each can take several
  /// requests (Plex Discover's match, its search, metadata probes).
  static const int maxChecksPerRun = 10;

  static const int maxEntries = 500;

  static final Map<String, LocalWatchlist> _instances = {};

  LocalWatchlist._(this.profileId);

  factory LocalWatchlist.forProfile(String? profileId) {
    final id = profileId ?? '';
    return _instances.putIfAbsent(id, () => LocalWatchlist._(id));
  }

  final String profileId;

  List<LocalWatchlistEntry> _entries = const [];
  Future<void>? _loading;
  bool _loaded = false;
  bool _promoting = false;

  static String keyOf(String serverId, String itemId) => '$serverId/$itemId';

  String get _key => profileScopedPrefsKey(profileId, baseKey);

  Future<void> ensureLoaded() => _loading ??= _load();

  /// [ensureLoaded], without a wait once the list has been read: the provider
  /// reads it on every profile switch, so the watchlist and the menus need not
  /// queue behind a future that finished long ago.
  Future<void> _ready() async {
    if (!_loaded) await ensureLoaded();
  }

  Future<void> _load() async {
    final before = _entries;
    try {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final raw = prefs.getString(_key);
      final decoded = raw == null || raw.isEmpty ? null : jsonDecode(raw);
      _entries = [
        if (decoded is List)
          for (final entry in decoded) ?LocalWatchlistEntry.fromJson(entry),
      ];
      if (_entries.isNotEmpty || before.isNotEmpty) notifyListeners();
    } catch (error, stackTrace) {
      appLogger.w('Local watchlist: load failed', error: error, stackTrace: stackTrace);
      _entries = const [];
    } finally {
      _loaded = true;
    }
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      if (_entries.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, jsonEncode([for (final entry in _entries) entry.toJson()]));
      }
    } catch (error, stackTrace) {
      appLogger.w('Local watchlist: save failed', error: error, stackTrace: stackTrace);
    }
  }

  /// Every entry, newest first, handed-over ones included.
  List<LocalWatchlistEntry> get entries => _entries;

  /// The entries waiting for [source] or standing in for it.
  List<LocalWatchlistEntry> entriesFor(CatalogSourceId source) => [
    for (final entry in _entries)
      if (entry.source == source) entry,
  ];

  LocalWatchlistEntry? _entryFor(MediaItem item) {
    final serverId = item.serverId;
    if (serverId == null) return null;
    final key = keyOf(serverId, item.id);
    return _entries.firstWhereOrNull((entry) => entry.key == key);
  }

  /// Whether the app itself holds [item]. A handed-over entry does not count:
  /// from then on the provider's own membership answers.
  bool holds(MediaItem item) => _entryFor(item)?.isPromoted == false;

  /// Keep [item] for [source].
  Future<void> add(MediaItem item, {required CatalogSourceId source}) async {
    final serverId = item.serverId;
    if (serverId == null) return;
    await _ready();
    final key = keyOf(serverId, item.id);
    _entries = [
      LocalWatchlistEntry(
        serverId: serverId,
        itemId: item.id,
        backend: item.backend,
        kind: item.kind,
        title: item.title ?? '',
        year: item.year,
        source: source,
        // Just asked: the press that lands here has looked already.
        addedAt: clock.now(),
        checkedAt: clock.now(),
      ),
      for (final entry in _entries)
        if (entry.key != key) entry,
    ].take(maxEntries).toList();
    await _save();
  }

  /// Drop [item], handed over or not.
  Future<void> remove(MediaItem item) async {
    final entry = _entryFor(item);
    if (entry == null) return;
    await _drop({entry.key});
  }

  Future<void> _drop(Set<String> keys) async {
    if (keys.isEmpty) return;
    _entries = [
      for (final entry in _entries)
        if (!keys.contains(entry.key)) entry,
    ];
    await _save();
  }

  Future<void> _replace(LocalWatchlistEntry updated) async {
    _entries = [for (final entry in _entries) entry.key == updated.key ? updated : entry];
    await _save();
  }

  /// Hand [item] to the provider of [candidate], which knows it now.
  Future<void> promote(MediaItem item, WatchlistCandidate candidate) async {
    final entry = _entryFor(item);
    if (entry == null || entry.isPromoted || entry.source != candidate.source.id) return;
    await _promote(entry, candidate);
  }

  Future<void> _promote(LocalWatchlistEntry entry, WatchlistCandidate candidate) async {
    await mutateWatchlistMembership(entry.kind, candidate, add: true);
    await _replace(entry._copy(promotedAt: clock.now(), promotedIds: candidate.ids));
    appLogger.i('Local watchlist: "${entry.title}" handed to ${candidate.source.id.name}');
  }

  /// Ask [source] about the entries waiting for it that are due, and hand over
  /// what it knows now.
  Future<void> promoteDue(CatalogSource source, MediaServerClient? Function(String serverId) clientFor) async {
    if (_promoting) return;
    _promoting = true;
    try {
      await _ready();
      final now = clock.now();
      final due = [
        for (final entry in entriesFor(source.id))
          if (!entry.isPromoted && (entry.checkedAt == null || now.difference(entry.checkedAt!) >= recheckInterval))
            entry,
      ].take(maxChecksPerRun);
      for (final entry in due) {
        final client = clientFor(entry.serverId);
        if (client == null) continue;
        try {
          final external = await client.fetchExternalIds(entry.itemId);
          final ids = external.hasAny ? await source.resolveItemIds(entry.kind, external, title: entry.title) : null;
          if (ids == null) {
            await _replace(entry._copy(checkedAt: clock.now()));
          } else {
            await _promote(entry, (source: source, ids: ids));
          }
        } catch (error, stackTrace) {
          appLogger.d('Local watchlist: check of "${entry.title}" failed', error: error, stackTrace: stackTrace);
          await _replace(entry._copy(checkedAt: clock.now()));
        }
      }
    } finally {
      _promoting = false;
    }
  }

  /// The entries the watchlist of [source] shows beside the provider's own
  /// [listed] titles. A handed-over entry is shown until the provider's list
  /// has it, or the grace has run out; either way it is then forgotten.
  Future<List<LocalWatchlistEntry>> shownBeside(CatalogSourceId source, List<MediaItem> listed) async {
    await _ready();
    final listedKeys = <String>{
      for (final item in listed)
        if (item.catalogItem case final catalog?) ...catalog.ids.allKeys,
    };
    final now = clock.now();
    final shown = <LocalWatchlistEntry>[];
    final done = <String>{};
    for (final entry in entriesFor(source)) {
      if (entry.isPromoted) {
        final arrived = entry.promotedIds?.allKeys.any(listedKeys.contains) ?? false;
        if (arrived || now.difference(entry.promotedAt!) >= promotedGrace) {
          done.add(entry.key);
          continue;
        }
      }
      shown.add(entry);
    }
    await _drop(done);
    return shown;
  }

  /// Read every profile's list afresh — after a restore wrote the stored ones.
  static void reloadAll() {
    for (final list in _instances.values) {
      list._loading = null;
      unawaited(list.ensureLoaded());
    }
  }

  /// Test seam: drop every cached profile list.
  @visibleForTesting
  static void debugReset() => _instances.clear();
}
