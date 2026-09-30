import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../database/app_database.dart';
import '../../i18n/strings.g.dart';
import '../../media/catalog_item_ref.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import '../settings_service.dart';
import 'tmdb_client.dart';

/// Fills in what the media server did not supply — clear logos, and the
/// description text catalog rows arrive without — from the user's own TMDB
/// account.
///
/// Plex only carries a logo when its agent or a poster tool supplied one, which
/// for most libraries is a small minority of titles; the rest fall back to
/// plain title text in the hero and spotlight. Jellyfin fares better but is not
/// complete either. Catalog rows (Explore) carry no overview at all: providers
/// only return one with their detail payload.
///
/// Every answer is cached, and that is the point rather than an optimization:
/// resolving one title costs a request to the media server (for its external
/// ids) plus one to TMDB, and the surfaces that show logos rebuild constantly
/// while a rail is being scrolled. So:
///
/// * results live in the [ArtworkLookups] table and survive restarts;
/// * misses are cached too — a title TMDB has nothing for is asked about once,
///   not on every frame;
/// * logo and description come from one request, so the second costs nothing;
/// * episodes and seasons resolve under their series key, so zapping through
///   Continue Watching costs one lookup per series rather than per episode;
/// * concurrent callers for the same key share one in-flight future.
///
/// A failed lookup is never surfaced to the user. Artwork is decoration: the
/// title text stays where it was and the app carries on.
class TmdbFillInService {
  /// Long enough that a library is looked up once and then left alone; short
  /// enough that artwork added to TMDB later still arrives eventually.
  static const Duration hitTtl = Duration(days: 30);

  /// Misses expire sooner than hits: "TMDB has no logo yet" is the answer most
  /// likely to change, and re-asking costs one request per title per week.
  static const Duration missTtl = Duration(days: 7);

  static TmdbFillInService? _instance;

  static TmdbFillInService? get instanceOrNull => _instance;

  static void initialize(AppDatabase db, {TmdbClient Function(String credential)? clientFactory}) {
    final service = TmdbFillInService._(db, clientFactory ?? TmdbClient.new);
    _instance = service;
    unawaited(service.warmUp());
  }

  @visibleForTesting
  static void resetForTesting() {
    _instance?._disposeClient();
    _instance = null;
  }

  TmdbFillInService._(this._db, this._clientFactory);

  final AppDatabase _db;
  final TmdbClient Function(String credential) _clientFactory;

  /// Answers already resolved this session, including empty ones.
  final Map<String, TmdbFillIn> _resolved = {};
  final Map<String, Future<TmdbFillIn>> _inFlight = {};

  /// Filmographies by person name, for this session only: they are large, and
  /// which titles the viewer owns can change under them.
  final Map<String, List<TmdbCredit>> _filmographies = {};
  final Map<String, Future<List<TmdbCredit>>> _filmographyLoads = {};

  TmdbClient? _client;
  String? _clientCredential;

  /// The stored key, whether or not the feature is switched on. Read on every
  /// call so a key entered in settings takes effect without a restart.
  ///
  /// Deliberately independent of [isEnabled]: settings can check a key before
  /// the switch is turned on, and reporting "TMDB rejected the key" for a
  /// switch that is merely off would be a lie.
  String? get credential {
    final key = SettingsService.instanceOrNull?.read(SettingsService.tmdbApiKey)?.trim();
    return key == null || key.isEmpty ? null : key;
  }

  /// Whether lookups may actually happen: a key *and* the switch.
  bool get isEnabled =>
      credential != null && (SettingsService.instanceOrNull?.read(SettingsService.tmdbLogosEnabled) ?? false);

  /// A client for the stored key, rebuilt when the key changes.
  TmdbClient? get _currentClient {
    final key = credential;
    if (key == null) return null;
    if (_client == null || _clientCredential != key) {
      _disposeClient();
      _client = _clientFactory(key);
      _clientCredential = key;
    }
    return _client;
  }

  void _disposeClient() {
    _client?.dispose();
    _client = null;
    _clientCredential = null;
  }

  /// What is already known about [item], without waiting for anything.
  ///
  /// Widgets check this before their first paint: an answer that only arrives
  /// a frame later makes the title text flash up and then be replaced, which
  /// looks like a glitch even though nothing went wrong. Null means "not known
  /// yet", which is not the same as "nothing to be had" — for that, wait for
  /// [resolve].
  TmdbFillIn? known(MediaItem item) {
    if (!isEnabled) return null;
    final subject = _subjectFor(item);
    if (subject == null) return null;
    return _resolved['${subject.cacheKey}:$_language'];
  }

  /// Whether [item] can be looked up at all, so a caller can tell an answer
  /// that is merely late from one that is never coming.
  bool canResolve(MediaItem item) => isEnabled && _subjectFor(item) != null;

  /// What TMDB can add for [item]; empty when there is nothing to be had.
  ///
  /// [client] is the media server the item came from; without it only items
  /// that already carry a TMDB id (catalog rows) can be resolved, because the
  /// external ids of a library item live on the server.
  Future<TmdbFillIn> resolve(MediaItem item, {MediaServerClient? client}) async {
    if (!isEnabled) return const TmdbFillIn();

    final subject = _subjectFor(item);
    if (subject == null) return const TmdbFillIn();

    final key = '${subject.cacheKey}:$_language';
    final known = _resolved[key];
    if (known != null) return known;

    final existing = _inFlight[key];
    if (existing != null) return existing;

    final pending = _lookup(key, subject, client);
    _inFlight[key] = pending;
    try {
      return await pending;
    } finally {
      // Map.remove hands back the future it dropped; nothing awaits it here.
      unawaited(_inFlight.remove(key));
    }
  }

  Future<TmdbFillIn> _lookup(String key, _FillInSubject subject, MediaServerClient? client) async {
    final cached = await _readCache(key);
    if (cached != null) {
      _resolved[key] = cached;
      return cached;
    }

    final tmdb = _currentClient;
    if (tmdb == null) return const TmdbFillIn();

    final resolved = await _resolveTmdbId(subject, client, tmdb);
    if (resolved.id == null) {
      // "This title is not on TMDB" is a durable answer worth storing. "I could
      // not ask" is not — caching that would leave a title bare for the whole
      // TTL because the server happened to be busy once.
      if (resolved.conclusive) await _remember(key, const TmdbFillIn());
      return const TmdbFillIn();
    }

    final found = await tmdb.fetchFillIn(
      isMovie: subject.isMovie,
      tmdbId: resolved.id!,
      languages: _languagePreference,
    );
    final fillIn = found.fillIn;
    if (!found.conclusive || fillIn == null) return const TmdbFillIn();
    await _remember(key, fillIn);
    return fillIn;
  }

  /// Everything TMDB credits [personName] with, given the title the viewer
  /// reached them from.
  ///
  /// Empty when the feature is off, when the title cannot be resolved, or when
  /// the person is not in that title's TMDB cast — never a guess. Remembered
  /// for the session, because walking into a filmography and back out again is
  /// exactly what people do.
  Future<List<TmdbCredit>> filmographyFor({
    required MediaItem sourceTitle,
    required String personName,
    MediaServerClient? client,
  }) async {
    if (!isEnabled) return const [];

    final cached = _filmographies[personName];
    if (cached != null) return cached;

    final pending = _filmographyLoads.putIfAbsent(
      personName,
      () => _loadFilmography(sourceTitle: sourceTitle, personName: personName, client: client),
    );
    try {
      return await pending;
    } finally {
      unawaited(_filmographyLoads.remove(personName));
    }
  }

  Future<List<TmdbCredit>> _loadFilmography({
    required MediaItem sourceTitle,
    required String personName,
    MediaServerClient? client,
  }) async {
    final tmdb = _currentClient;
    final subject = _subjectFor(sourceTitle);
    if (tmdb == null || subject == null) return const [];

    final title = await _resolveTmdbId(subject, client, tmdb);
    if (title.id == null) return const [];

    final personId = await tmdb.personIdInCast(isMovie: subject.isMovie, tmdbId: title.id!, name: personName);
    if (personId == null) return const [];

    final credits = await tmdb.personCredits(personId: personId, languages: _languagePreference);
    _filmographies[personName] = credits;
    return credits;
  }

  /// Stores an answer both for this session and for the next launch.
  Future<void> _remember(String key, TmdbFillIn fillIn) async {
    _resolved[key] = fillIn;
    await _writeCache(key, fillIn);
  }

  /// The TMDB id for [subject], and whether the answer is worth caching.
  Future<({int? id, bool conclusive})> _resolveTmdbId(
    _FillInSubject subject,
    MediaServerClient? client,
    TmdbClient tmdb,
  ) async {
    if (subject.ids.tmdb != null) return (id: subject.ids.tmdb, conclusive: true);

    var ids = subject.ids;
    final serverItemId = subject.serverItemId;
    if (!ids.hasCatalogIds) {
      // Without a server to ask there is nothing to conclude — a library item
      // keeps its external ids on the server, and the client is only missing
      // while one is still binding.
      if (client == null || serverItemId == null) return (id: null, conclusive: false);
      try {
        ids = ids.fillFrom(await client.fetchExternalIds(serverItemId));
      } catch (e) {
        appLogger.d('TMDB fill-in: external ids failed for $serverItemId', error: e);
        return (id: null, conclusive: false);
      }
    }
    // The server answered and knows no catalog id for this title; nothing will
    // change that until the item is rematched, so the miss is worth storing.
    if (!ids.hasCatalogIds) return (id: null, conclusive: true);
    return tmdb.resolveId(isMovie: subject.isMovie, ids: ids);
  }

  /// What to look up for [item]: the item itself for movies and shows, the
  /// series for anything below one. Music has no clear logos and is skipped.
  static _FillInSubject? _subjectFor(MediaItem item) {
    if (item.kind.isMusic) return null;

    final catalog = item.catalogItem;
    if (catalog != null) {
      return _FillInSubject(
        cacheKey: item.id,
        isMovie: catalog.kind == MediaKind.movie,
        ids: catalog.ids.toExternalIds(),
      );
    }

    return switch (item.kind) {
      MediaKind.movie => _FillInSubject(cacheKey: item.globalKey, isMovie: true, serverItemId: item.id),
      MediaKind.show => _FillInSubject(cacheKey: item.globalKey, isMovie: false, serverItemId: item.id),
      MediaKind.episode || MediaKind.season => switch (item.seriesGlobalKey) {
        final String seriesKey => _FillInSubject(
          cacheKey: seriesKey,
          isMovie: false,
          // The show's own rating key, not the episode's — external ids are
          // recorded on the series.
          serverItemId: item.grandparentId ?? item.parentId,
        ),
        null => null,
      },
      _ => null,
    };
  }

  /// Device language first, English second. Two entries rather than one: a
  /// German logo is what the rest of the app's metadata looks like, but an
  /// English one still beats plain text.
  List<String> get _languagePreference {
    final language = _language;
    return language == 'en' ? const ['en'] : [language, 'en'];
  }

  String get _language => LocaleSettings.currentLocale.languageCode;

  /// The stored answer, or null when nothing fresh is on record. A stored
  /// answer may be empty — that is the cached miss.
  Future<TmdbFillIn?> _readCache(String key) async {
    try {
      final row = await (_db.select(_db.artworkLookups)..where((t) => t.lookupKey.equals(key))).getSingleOrNull();
      if (row == null) return null;
      final found = TmdbFillIn(
        logoUrl: row.url.isEmpty ? null : row.url,
        summary: row.summary.isEmpty ? null : row.summary,
      );
      if (_isStale(row.resolvedAt, found)) return null;
      return found;
    } catch (e) {
      appLogger.d('TMDB fill-in cache read failed for $key', error: e);
      return null;
    }
  }

  Future<void> _writeCache(String key, TmdbFillIn fillIn) async {
    try {
      await _db
          .into(_db.artworkLookups)
          .insertOnConflictUpdate(
            ArtworkLookupsCompanion.insert(
              lookupKey: key,
              url: fillIn.logoUrl ?? '',
              summary: Value(fillIn.summary ?? ''),
              resolvedAt: Value(DateTime.now()),
            ),
          );
    } catch (e) {
      appLogger.d('TMDB fill-in cache write failed for $key', error: e);
    }
  }

  /// Reads stored answers into memory so the first paint of a title already
  /// knows them.
  ///
  /// Without this, every title flashes its plain name once per launch while a
  /// database read that takes a millisecond lands after the frame that needed
  /// it. Capped, because the cache grows with everything the user has ever
  /// browsed and only the recent end of it is about to be on screen.
  Future<void> warmUp({int limit = 2000}) async {
    if (!isEnabled) return;
    try {
      final rows =
          await (_db.select(_db.artworkLookups)
                ..orderBy([(t) => OrderingTerm.desc(t.resolvedAt)])
                ..limit(limit))
              .get();
      for (final row in rows) {
        final found = TmdbFillIn(
          logoUrl: row.url.isEmpty ? null : row.url,
          summary: row.summary.isEmpty ? null : row.summary,
        );
        if (_isStale(row.resolvedAt, found)) continue;
        _resolved.putIfAbsent(row.lookupKey, () => found);
      }
    } catch (e) {
      appLogger.d('TMDB fill-in warm-up failed', error: e);
    }
  }

  bool _isStale(DateTime resolvedAt, TmdbFillIn found) =>
      DateTime.now().difference(resolvedAt) > (found.isEmpty ? missTtl : hitTtl);

  /// Drops every stored lookup. Offered in settings because a key change or a
  /// wave of newly added artwork are the two cases where waiting out the TTL
  /// is the wrong answer.
  Future<void> clearCache() async {
    _resolved.clear();
    _filmographies.clear();
    await _db.delete(_db.artworkLookups).go();
  }

  /// Whether TMDB accepts the credential currently stored in settings.
  Future<bool> verifyCredential() async {
    final tmdb = _currentClient;
    if (tmdb == null) return false;
    return tmdb.verifyCredential();
  }
}

/// The title a lookup runs for, once episodes and seasons have been folded
/// into their series.
class _FillInSubject {
  const _FillInSubject({
    required this.cacheKey,
    required this.isMovie,
    this.serverItemId,
    this.ids = const ExternalIds(),
  });

  final String cacheKey;
  final bool isMovie;

  /// The id to ask the media server for external ids with, when the subject
  /// came from a library rather than a catalog.
  final String? serverItemId;

  /// Ids already known without asking anyone — catalog rows carry them.
  final ExternalIds ids;
}
