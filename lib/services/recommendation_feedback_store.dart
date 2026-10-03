import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../profiles/profile.dart';
import '../utils/app_logger.dart';
import 'base_shared_preferences_service.dart';

/// A title the viewer asked for more of, as the recommendation row needs it:
/// enough to ask its server "what is like this", and the key that identifies
/// it across servers.
@immutable
class RecommendationLike {
  const RecommendationLike({
    required this.key,
    required this.id,
    required this.serverId,
    required this.backend,
    required this.kind,
    required this.title,
    this.year,
    required this.at,
  });

  /// Copy key — kind, title and year — see `RecommendationsService.copyKeyOf`.
  final String key;
  final String id;
  final String? serverId;
  final MediaBackend backend;
  final MediaKind kind;
  final String title;
  final int? year;
  final DateTime at;

  MediaItem toItem() => MediaItem(id: id, backend: backend, kind: kind, title: title, year: year, serverId: serverId);

  Map<String, Object?> toJson() => {
    'key': key,
    'id': id,
    'serverId': serverId,
    'backend': backend.id,
    'kind': kind.id,
    'title': title,
    'year': year,
    'at': at.millisecondsSinceEpoch,
  };

  static RecommendationLike? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final id = raw['id'];
    final at = raw['at'];
    if (key is! String || id is! String || at is! int) return null;
    return RecommendationLike(
      key: key,
      id: id,
      serverId: raw['serverId'] as String?,
      backend: MediaBackend.fromString(raw['backend'] as String?),
      kind: MediaKind.fromString(raw['kind'] as String?),
      title: raw['title'] as String? ?? '',
      year: raw['year'] as int?,
      at: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
}

/// A title the viewer asked for less of: kept out of the row, and the titles
/// its server called like it held back — for [RecommendationFeedbackStore.lessLifetime].
@immutable
class RecommendationDislike {
  const RecommendationDislike({required this.key, required this.at, this.related = const {}});

  final String key;
  final DateTime at;

  /// Copy keys of what its server named as like it.
  final Set<String> related;

  Map<String, Object?> toJson() => {'key': key, 'at': at.millisecondsSinceEpoch, 'related': related.toList()};

  static RecommendationDislike? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final at = raw['at'];
    if (key is! String || at is! int) return null;
    final related = raw['related'];
    return RecommendationDislike(
      key: key,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      related: related is List ? {for (final value in related) ?(value is String ? value : null)} : const {},
    );
  }
}

/// "Mehr davon" and "Weniger davon" from the recommendation row's menu, per
/// profile, on this device.
///
/// A like is a seed the row draws on in turn with the favourites; a dislike
/// keeps its title out of the row and holds back what is like it, and lapses
/// after [lessLifetime] — the user's call, so a title can come back one day.
/// Both are capped so the store cannot grow without bound.
class RecommendationFeedbackStore {
  static const String _baseKey = 'recommendation_feedback';

  /// How long a "Weniger davon" holds.
  static const Duration lessLifetime = Duration(days: 182);

  static const int maxLikes = 50;
  static const int maxDislikes = 200;

  static final Map<String, RecommendationFeedbackStore> _instances = {};

  RecommendationFeedbackStore._(this.profileId);

  factory RecommendationFeedbackStore.forProfile(String? profileId) {
    final id = profileId ?? '';
    return _instances.putIfAbsent(id, () => RecommendationFeedbackStore._(id));
  }

  final String profileId;

  List<RecommendationLike> _likes = const [];
  List<RecommendationDislike> _dislikes = const [];
  Future<void>? _loading;

  String get _key => profileId.isEmpty ? _baseKey : profileScopedPrefsKey(profileId, _baseKey);

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final likes = decoded['more'];
      final dislikes = decoded['less'];
      _likes = [
        if (likes is List)
          for (final entry in likes) ?RecommendationLike.fromJson(entry),
      ];
      _dislikes = [
        if (dislikes is List)
          for (final entry in dislikes) ?RecommendationDislike.fromJson(entry),
      ];
    } catch (error, stackTrace) {
      // A corrupt entry must not take the recommendation row down with it.
      appLogger.w('Recommendation feedback: load failed', error: error, stackTrace: stackTrace);
      _likes = const [];
      _dislikes = const [];
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      if (_likes.isEmpty && _dislikes.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(
          _key,
          jsonEncode({
            'more': [for (final like in _likes) like.toJson()],
            'less': [for (final dislike in _dislikes) dislike.toJson()],
          }),
        );
      }
    } catch (error, stackTrace) {
      appLogger.w('Recommendation feedback: save failed', error: error, stackTrace: stackTrace);
    }
  }

  /// The titles asked for more of, newest first.
  List<RecommendationLike> get likes => _likes;

  /// The dislikes still in force; lapsed ones are dropped as they are passed.
  List<RecommendationDislike> get dislikes {
    final cutoff = clock.now().subtract(lessLifetime);
    final live = [
      for (final dislike in _dislikes)
        if (dislike.at.isAfter(cutoff)) dislike,
    ];
    if (live.length != _dislikes.length) {
      _dislikes = live;
      _save();
    }
    return live;
  }

  /// "Mehr davon" for [item] under [key]; a dislike of the same title goes.
  Future<void> like(MediaItem item, String key) async {
    await ensureLoaded();
    _dislikes = [
      for (final dislike in _dislikes)
        if (dislike.key != key) dislike,
    ];
    _likes = [
      RecommendationLike(
        key: key,
        id: item.id,
        serverId: item.serverId,
        backend: item.backend,
        kind: item.kind,
        title: item.title ?? '',
        year: item.year,
        at: clock.now(),
      ),
      for (final like in _likes)
        if (like.key != key) like,
    ].take(maxLikes).toList();
    await _save();
  }

  /// "Weniger davon" for the title under [key]; a like of it goes.
  Future<void> dislike(String key) async {
    await ensureLoaded();
    _likes = [
      for (final like in _likes)
        if (like.key != key) like,
    ];
    _dislikes = [
      RecommendationDislike(key: key, at: clock.now()),
      for (final dislike in _dislikes)
        if (dislike.key != key) dislike,
    ].take(maxDislikes).toList();
    await _save();
  }

  /// What the server named as like the disliked title under [key], once asked.
  Future<void> setDislikeRelated(String key, Set<String> related) async {
    await ensureLoaded();
    _dislikes = [
      for (final dislike in _dislikes)
        dislike.key == key ? RecommendationDislike(key: key, at: dislike.at, related: related) : dislike,
    ];
    await _save();
  }

  /// Forget every like and dislike of this profile.
  Future<void> clear() async {
    await ensureLoaded();
    _likes = const [];
    _dislikes = const [];
    await _save();
  }

  /// Test seam: drop every cached profile store.
  @visibleForTesting
  static void debugReset() => _instances.clear();
}
