import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_hub.dart';
import '../media/catalog_item_ref.dart';
import '../media/media_backend.dart';
import '../media/media_server_client.dart';
import '../media/ultra_blur_colors.dart';
import '../models/catalog/catalog_item.dart';
import '../providers/catalog_sources_provider.dart';
import '../providers/discover_provider.dart';
import '../providers/multi_server_provider.dart';
import '../screens/live_now/live_now_loader.dart';
import '../theme/mono_tokens.dart';
import '../utils/app_logger.dart';
import 'catalog/catalog_source.dart';
import 'home_rows.dart';
import 'plex_client.dart';
import 'sport/sport_league_names.dart';
import 'sport/sport_models.dart';
import 'sport/sport_repository.dart';
import 'settings_service.dart';

/// Feeds [HomeRows] from the start page (Plebz).
///
/// The start page makes one while it is mounted. It watches the
/// [DiscoverProvider] for Continue Watching and the recommendations, takes
/// "Jetzt live" from the start page as that refreshes, and reads the first
/// page of the watchlist itself, at most every quarter of an hour. A change of
/// profile empties the snapshot before the new profile's rows go in.
class HomeRowsFeed {
  HomeRowsFeed({
    required this.discover,
    required this.multiServer,
    this.catalog,
    HomeRows? rows,
    SportRepository? sport,
  }) : rows = rows ?? HomeRows.instance,
       sport = sport ?? SportRepository.instance {
    discover.addListener(_onDiscoverChanged);
    _onDiscoverChanged();
  }

  static const Duration watchlistInterval = Duration(minutes: 15);
  static const int watchlistLimit = 20;

  final DiscoverProvider discover;
  final MultiServerProvider multiServer;
  final CatalogSourcesProvider? catalog;
  final HomeRows rows;
  final SportRepository sport;

  String? _profile;
  List<MediaItem>? _seenOnDeck;
  MediaHub? _seenRecommendations;
  DateTime? _watchlistAt;
  bool _watchlistLoading = false;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    discover.removeListener(_onDiscoverChanged);
  }

  /// The app's look, for the launcher to match.
  void takeTheme(BuildContext context) {
    final tk = Theme.of(context).extension<MonoTokens>();
    if (tk == null) return;
    final variant = SettingsService.instanceOrNull?.read(PlebzPrefs.appThemeVariant).name ?? 'standard';
    final fullCards = SettingsService.instanceOrNull?.read(SettingsService.tvFullCardLayout) ?? false;
    rows.setTheme(
      HomeRowsTheme(variant: variant, accent: tk.accent, background: tk.bg, text: tk.text, fullCards: fullCards),
    );
  }

  /// "Jetzt live" as the start page has just loaded it — and with it, as
  /// often, the leagues' matchdays for a launcher's sport section.
  void takeLiveNow(LiveNowSnapshot snapshot) {
    final now = DateTime.now();
    rows.publish(HomeRows.liveNowRow, t.discover.liveNow, [
      for (final entry in snapshot.entries) homeRowTileForLiveNow(entry, clientFor: _client, now: now),
    ]);
    unawaited(refreshSport());
  }

  bool _sportLoading = false;

  /// The current matchday of each league (the Sport page's, by its Tuesday
  /// rule), as rows: the favourite club's league marked to open on. The
  /// repository keeps each answer as long as it can change, so asking with
  /// every minute's "Jetzt live" costs a request only when one is due.
  Future<void> refreshSport() async {
    if (_sportLoading || _disposed || !rows.supported) return;
    _sportLoading = true;
    try {
      final favourite = SettingsService.instanceOrNull?.read(PlebzPrefs.sportFavouriteClub);
      final now = DateTime.now();
      final visible = visibleSportLeagues();
      for (final league in SportLeague.values) {
        if (!visible.contains(league)) rows.publish(HomeRows.sportRow(league), sportLeagueName(league), const []);
      }
      for (final league in visible) {
        final current = await sport.current(league);
        if (_disposed) return;
        if (current == null) continue;
        final matches = [...current.matches]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
        rows.publish(
          HomeRows.sportRow(league),
          sportLeagueName(league),
          [for (final match in matches) homeRowTileForMatch(match, now: now)],
          subtitle: homeRowsMatchdayLine(current.matchday, matches),
          selected:
              favourite != null &&
              favourite > 0 &&
              matches.any((match) => match.home.id == favourite || match.away.id == favourite),
        );
      }
    } catch (e) {
      appLogger.d('Home rows: sport unavailable', error: e);
    } finally {
      _sportLoading = false;
    }
  }

  void _onDiscoverChanged() {
    if (_disposed) return;
    final profile = discover.profileId;
    if (profile != _profile) {
      if (_profile != null) unawaited(rows.clear());
      _profile = profile;
      _seenOnDeck = null;
      _seenRecommendations = null;
      _watchlistAt = null;
    }
    final hideSpoilers = SettingsService.instanceOrNull?.read(SettingsService.hideSpoilers) ?? false;
    final posterMode =
        SettingsService.instanceOrNull?.read(SettingsService.episodePosterMode) ?? EpisodePosterMode.episodeThumbnail;
    // A tap on Continue Watching does what it does on the start page: the
    // title's page by default, playing on only where the viewer chose that.
    final openDetails =
        (SettingsService.instanceOrNull?.read(SettingsService.continueWatchingAction) ??
            ContinueWatchingAction.details) ==
        ContinueWatchingAction.details;

    final onDeck = discover.onDeck;
    if (!identical(onDeck, _seenOnDeck)) {
      _seenOnDeck = onDeck;
      void publish() => rows.publish(HomeRows.continueRow, t.discover.continueWatching, [
        for (final item in onDeck)
          ?homeRowTileForItem(
            item,
            client: _clientOf(item),
            resume: true,
            hideSpoilers: hideSpoilers,
            posterMode: posterMode,
            openDetails: openDetails,
            colours: _coloursOf(item),
          ),
      ]);
      publish();
      _fetchColours(onDeck, () {
        if (identical(onDeck, _seenOnDeck)) publish();
      });
    }

    final recommendations = discover.hubs.firstWhereOrNull((hub) => hub.id == recommendationsHubId);
    if (!identical(recommendations, _seenRecommendations)) {
      _seenRecommendations = recommendations;
      final items = recommendations?.items ?? const <MediaItem>[];
      void publish() => rows.publish(HomeRows.recommendationsRow, t.discover.recommendedForYou, [
        for (final item in items) ?homeRowTileForItem(item, client: _clientOf(item), colours: _coloursOf(item)),
      ]);
      publish();
      _fetchColours(items, () {
        if (identical(recommendations, _seenRecommendations)) publish();
      });
    }

    unawaited(refreshWatchlist());
  }

  /// The first page of the watchlist the Merkliste shows, unless it was read
  /// less than [watchlistInterval] ago.
  Future<void> refreshWatchlist({bool force = false}) async {
    final catalog = this.catalog;
    if (catalog == null || _watchlistLoading) return;
    final at = _watchlistAt;
    if (!force && at != null && DateTime.now().difference(at) < watchlistInterval) return;
    final sources = catalog.watchlistCapableSources;
    if (sources.isEmpty) return;
    final chosen = SettingsService.instanceOrNull?.read(PlebzPrefs.watchlistSource) ?? '';
    final source = sources.firstWhereOrNull((source) => source.id.name == chosen) ?? sources.first;
    _watchlistLoading = true;
    _watchlistAt = DateTime.now();
    try {
      final page = await source.fetchRow(CatalogRowId.watchlist, limit: watchlistLimit);
      if (_disposed) return;
      final items = page.items.map((entry) => entry.toMediaItem()).toList();
      void publish() => rows.publish(HomeRows.watchlistRow, t.explore.rows.watchlist, [
        for (final item in items) ?homeRowTileForItem(item, client: _clientOf(item), colours: _coloursOf(item)),
      ]);
      publish();
      _fetchColours(items, () {
        if (!_disposed) publish();
      });
    } catch (e) {
      appLogger.d('Home rows: watchlist unavailable', error: e);
    } finally {
      _watchlistLoading = false;
    }
  }

  /// Plex's four corner colours for each title, asked once a session and
  /// shared by every feed (the launcher's "Hintergrund in Posterfarben").
  static final LinkedHashMap<String, UltraBlurColors?> _colours = LinkedHashMap();
  static const int _coloursCacheSize = 400;

  UltraBlurColors? _coloursOf(MediaItem item) {
    final request = _colourRequestFor(item);
    return request == null ? null : _colours[request.key];
  }

  /// Asks Plex for the colours [items] lack, a few at a time, and calls
  /// [done] once any arrived. Only Plex derives them; others go without.
  void _fetchColours(List<MediaItem> items, VoidCallback done) {
    final missing = [
      for (final item in items)
        if (_colourRequestFor(item) case final request? when !_colours.containsKey(request.key)) request,
    ];
    if (missing.isEmpty) return;
    unawaited(() async {
      var found = false;
      for (var i = 0; i < missing.length && !_disposed; i += 4) {
        await Future.wait([
          for (final request in missing.skip(i).take(4))
            () async {
              UltraBlurColors? colours;
              try {
                colours = await request.client.fetchUltraBlurColors(request.url);
              } catch (error) {
                appLogger.d('Home rows: no colours for ${request.url}', error: error);
              }
              _colours[request.key] = colours;
              found = found || colours != null;
            }(),
        ]);
      }
      while (_colours.length > _coloursCacheSize) {
        _colours.remove(_colours.keys.first);
      }
      if (found && !_disposed) done();
    }());
  }

  /// The client and artwork Plex derives a title's colours from, as the
  /// start page asks for them.
  ({PlexClient client, String url, String key})? _colourRequestFor(MediaItem item) {
    final art = item.artPath, thumb = item.thumbPath;
    final url = art != null && art.isNotEmpty ? art : (thumb != null && thumb.isNotEmpty ? thumb : null);
    if (url == null) return null;
    if (item.isCatalogItem) {
      if (item.catalogItem?.source != CatalogSourceId.plex) return null;
      final client = multiServer.serverManager.onlineClients.values.whereType<PlexClient>().firstOrNull;
      return client == null ? null : (client: client, url: url, key: url);
    }
    final serverId = item.serverId;
    if (item.backend != MediaBackend.plex || serverId == null) return null;
    final client = multiServer.serverManager.getClient(ServerId(serverId));
    return client is PlexClient ? (client: client, url: url, key: '$serverId|$url') : null;
  }

  MediaServerClient? _clientOf(MediaItem item) {
    final serverId = item.serverId;
    return serverId == null ? null : _client(serverId);
  }

  MediaServerClient? _client(String serverId) => multiServer.getClientForServer(ServerId(serverId));
}
