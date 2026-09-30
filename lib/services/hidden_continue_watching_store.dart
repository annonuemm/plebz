import 'dart:async';
import 'dart:convert';

import '../media/media_item.dart';
import '../profiles/profile.dart';
import '../utils/app_logger.dart';
import 'base_shared_preferences_service.dart';

/// Locally hidden Continue Watching entries, for servers that cannot hide one
/// themselves.
///
/// Plex and Emby both have a route that drops an item from Continue Watching
/// while leaving its resume position alone, so on those the removal is a
/// server-side action every client sees. Jellyfin has no such route, so the
/// entry is remembered here instead — which means it only takes effect in this
/// app, and only for this profile.
///
/// A hidden entry is remembered together with the resume position it had when
/// it was hidden. That is what keeps "hide" from meaning "never show again":
/// once the item is played on any client its position moves, the remembered
/// one no longer matches, and the entry comes back on its own. Nothing has to
/// watch for that or clean up after it.
class HiddenContinueWatchingStore {
  static const String _baseKey = 'hidden_continue_watching';

  /// Resume positions drift by a second or two between reports; anything
  /// larger is real viewing and un-hides the entry.
  static const int positionToleranceMs = 5000;

  /// Position recorded for an item that has not been started yet, so a
  /// never-started next-up episode is still distinguishable from a resumed one.
  static const int _noPosition = -1;

  static final Map<String, HiddenContinueWatchingStore> _instances = {};

  HiddenContinueWatchingStore._(this.profileId);

  /// The store for one profile. Hidden entries are watch state, so they follow
  /// the profile the way the rest of watch state does.
  factory HiddenContinueWatchingStore.forProfile(String? profileId) {
    final id = profileId ?? '';
    return _instances.putIfAbsent(id, () => HiddenContinueWatchingStore._(id));
  }

  final String profileId;

  Map<String, int> _hidden = {};
  Future<void>? _loading;

  String get _key => profileId.isEmpty ? _baseKey : profileScopedPrefsKey(profileId, _baseKey);

  /// Loads once per profile; safe to await from anywhere.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _hidden = {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is int) entry.key as String: entry.value as int,
      };
    } catch (error, stackTrace) {
      // A corrupt entry must not take Continue Watching down with it.
      appLogger.w('Hidden Continue Watching: load failed', error: error, stackTrace: stackTrace);
      _hidden = {};
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      if (_hidden.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, jsonEncode(_hidden));
      }
    } catch (error, stackTrace) {
      appLogger.w('Hidden Continue Watching: save failed', error: error, stackTrace: stackTrace);
    }
  }

  static int _positionOf(MediaItem item) => item.viewOffsetMs ?? _noPosition;

  /// Whether [item] is hidden *at the position it was hidden at*. An item the
  /// user has watched further since is not hidden any more.
  bool isHidden(MediaItem item) {
    final stored = _hidden[item.globalKey];
    if (stored == null) return false;
    return (stored - _positionOf(item)).abs() <= positionToleranceMs;
  }

  /// Hide [item] until its resume position moves.
  Future<void> hide(MediaItem item) async {
    await ensureLoaded();
    _hidden = {..._hidden, item.globalKey: _positionOf(item)};
    await _save();
  }

  /// Show every hidden entry again.
  Future<void> clear() async {
    await ensureLoaded();
    if (_hidden.isEmpty) return;
    _hidden = {};
    await _save();
  }

  int get hiddenCount => _hidden.length;

  /// [items] without the entries hidden at their current position.
  ///
  /// Entries whose item has moved on are dropped from the store as they are
  /// passed over, so the map cannot grow without bound.
  List<MediaItem> visible(List<MediaItem> items) {
    if (_hidden.isEmpty) return items;
    final stale = <String>[];
    final result = <MediaItem>[];
    for (final item in items) {
      if (isHidden(item)) continue;
      if (_hidden.containsKey(item.globalKey)) stale.add(item.globalKey);
      result.add(item);
    }
    if (stale.isNotEmpty) {
      _hidden = {..._hidden}..removeWhere((key, _) => stale.contains(key));
      unawaited(_save());
    }
    return result;
  }

  /// Test seam: drop every cached profile store.
  static void debugReset() => _instances.clear();
}
