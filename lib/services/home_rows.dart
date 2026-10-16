import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../media/ultra_blur_colors.dart';
import '../models/livetv_channel.dart';
import '../screens/live_now/live_now_loader.dart';
import '../screens/live_now/live_now_tile.dart';
import 'package:intl/intl.dart';

import '../i18n/app_locale_utils.dart';
import '../i18n/strings.g.dart';
import '../utils/app_logger.dart';
import '../utils/content_utils.dart';
import '../utils/formatters.dart';
import '../utils/media_image_helper.dart';
import '../widgets/media_rating_badge.dart';
import 'settings_service.dart' show EpisodePosterMode;
import 'sport/club_colours.dart';
import 'sport/sport_models.dart';

/// The home rows a launcher signed with the app's key shows, kept for it by
/// the app (Plebz).
///
/// The app's screens hand their rows in as they load them — "Jetzt live",
/// Continue Watching, the watchlist, the recommendations — and this puts them
/// together into one snapshot for `HomeRowsProvider` on the Android side,
/// which serves it only to apps signed with the app's own key. Artwork goes
/// over as keys: the addresses behind them carry server credentials and stay
/// in the app, which fetches the pictures itself.
///
/// Android only; elsewhere every call does nothing.
class HomeRows {
  HomeRows({
    this.channel = const MethodChannel('app.plebz/home_rows'),
    bool? supported,
    this.debounce = const Duration(seconds: 1),
  }) : _supported = supported ?? (!kIsWeb && Platform.isAndroid);

  static final HomeRows instance = HomeRows();

  static const int schema = 1;

  /// The order the rows stand in, whatever order they arrive in.
  static const List<String> rowOrder = [liveNowRow, continueRow, watchlistRow, recommendationsRow];
  static const String liveNowRow = 'live_now';
  static const String continueRow = 'continue';
  static const String watchlistRow = 'watchlist';
  static const String recommendationsRow = 'recommendations';

  final MethodChannel channel;
  final bool _supported;

  /// Whether the rows go anywhere here (Android); elsewhere nothing is worth
  /// fetching for them.
  bool get supported => _supported;
  final Duration debounce;

  final Map<String, ({String title, List<HomeRowTile> tiles, String? subtitle, bool selected})> _rows = {};
  HomeRowsTheme? _theme;
  Timer? _timer;

  /// What the last write held, without its time ([buildPayload]'s content).
  String? _lastSnapshot;

  /// Replaces the row [id]; an empty [tiles] takes it away. [subtitle] says
  /// a word about the row (a league's matchday), [selected] marks the one of
  /// a group to open on (the favourite club's league).
  void publish(String id, String title, List<HomeRowTile> tiles, {String? subtitle, bool selected = false}) {
    if (!_supported) return;
    if (tiles.isEmpty) {
      if (_rows.remove(id) == null) return;
    } else {
      _rows[id] = (title: title, tiles: List.unmodifiable(tiles), subtitle: subtitle, selected: selected);
    }
    _schedule();
  }

  /// The row of a league's current matchday, for a launcher's sport section.
  static String sportRow(SportLeague league) => 'sport:${league.shortcut}';

  /// The look a launcher can match: the app's design, accent and ground.
  void setTheme(HomeRowsTheme theme) {
    if (!_supported || theme == _theme) return;
    _theme = theme;
    _schedule();
  }

  /// Empties the snapshot — on a change of profile, before the next one's rows.
  Future<void> clear() async {
    if (!_supported) return;
    _timer?.cancel();
    _timer = null;
    _rows.clear();
    _lastSnapshot = null;
    try {
      await channel.invokeMethod<bool>('clear');
    } catch (e) {
      appLogger.d('Home rows: clear failed', error: e);
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(flush()));
  }

  /// Writes what changed since the last write, at once.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (!_supported) return;
    final payload = buildPayload();
    if (payload.content == _lastSnapshot) return;
    try {
      final ok = await channel.invokeMethod<bool>('publish', {
        'snapshot': payload.snapshot,
        'sources': payload.sources,
      });
      if (ok == true) _lastSnapshot = payload.content;
    } catch (e) {
      appLogger.d('Home rows: publish failed', error: e);
    }
  }

  /// The snapshot as it would be written, the artwork addresses by key, and
  /// [content]: the snapshot without its time, which says whether anything
  /// changed since the last write.
  @visibleForTesting
  ({String snapshot, Map<String, String> sources, String content}) buildPayload({DateTime? now}) {
    final sources = <String, String>{};
    String? art(String? address) {
      if (address == null || address.isEmpty) return null;
      final key = sha1.convert(utf8.encode(address)).toString();
      sources[key] = address;
      return 'content://app.plebz.homerows/art/$key';
    }

    final ids = [
      ...rowOrder.where(_rows.containsKey),
      ...(_rows.keys.where((id) => !rowOrder.contains(id)).toList()..sort()),
    ];
    final body = <String, dynamic>{
      'theme': ?_theme?.toJson(),
      'rows': [
        for (final id in ids)
          {
            'id': id,
            'title': _rows[id]!.title,
            'subtitle': ?_rows[id]!.subtitle,
            if (_rows[id]!.selected) 'selected': true,
            'items': [for (final tile in _rows[id]!.tiles) tile.toJson(art)],
          },
      ],
    };
    final content = jsonEncode(body);
    final snapshot = jsonEncode({
      'schema': schema,
      'updatedAt': (now ?? DateTime.now()).millisecondsSinceEpoch,
      ...body,
    });
    return (snapshot: snapshot, sources: sources, content: content);
  }

  @visibleForTesting
  void debugReset() {
    _timer?.cancel();
    _timer = null;
    _rows.clear();
    _theme = null;
    _lastSnapshot = null;
  }
}

/// The app's look, for a launcher to take on.
@immutable
class HomeRowsTheme {
  const HomeRowsTheme({
    required this.variant,
    required this.accent,
    required this.background,
    this.text,
    this.fullCards = false,
  });

  /// `standard`, `glas` or `flach`.
  final String variant;
  final Color accent;
  final Color background;

  /// The ink words are written in.
  final Color? text;

  /// "Volle Karten" on the TV: pictures without a caption under them.
  final bool fullCards;

  Map<String, dynamic> toJson() => {
    'variant': variant,
    'accent': _hex(accent),
    'background': _hex(background),
    if (text != null) 'text': _hex(text!),
    if (fullCards) 'fullCards': true,
  };

  @override
  bool operator ==(Object other) =>
      other is HomeRowsTheme &&
      other.variant == variant &&
      other.accent == accent &&
      other.background == background &&
      other.text == text &&
      other.fullCards == fullCards;

  @override
  int get hashCode => Object.hash(variant, accent, background, text, fullCards);
}

String _hex(Color color) => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The shape a tile's picture has.
enum HomeRowImageShape { poster, landscape, logo }

/// A team on a game's tile.
@immutable
class HomeRowTeam {
  const HomeRowTeam({required this.name, this.image, this.colour});

  final String name;

  /// The crest's address; the snapshot names it by key.
  final String? image;

  /// The colour the club is known by, for the tile's ground ("Jetzt live").
  final Color? colour;

  Map<String, dynamic> toJson(String? Function(String? address) art) => {
    'name': name,
    'image': ?art(image),
    if (colour != null) 'colour': _hex(colour!),
  };
}

/// One tile of a home row.
@immutable
class HomeRowTile {
  const HomeRowTile({
    required this.id,
    required this.kind,
    required this.title,
    required this.open,
    this.subtitle,
    this.image,
    this.imageShape,
    this.progress,
    this.startsAt,
    this.endsAt,
    this.live,
    this.home,
    this.away,
    this.score,
    this.backdrop,
    this.summary,
    this.facts = const [],
    this.badge,
    this.colours,
  });

  final String id;

  /// `movie`, `episode`, `show`, `season`, `game` or `channel`.
  final String kind;
  final String title;
  final String? subtitle;

  /// The picture's address; the snapshot names it by key.
  final String? image;
  final HomeRowImageShape? imageShape;

  /// 0 to 1: how much has been watched, or how far the programme is.
  final double? progress;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool? live;
  final HomeRowTeam? home;
  final HomeRowTeam? away;

  /// "2:1" while a game is on or once it is over.
  final String? score;

  /// The `plebz://` link a tap opens.
  final String open;

  /// For the launcher's spotlight over Continue Watching: the wide backdrop's
  /// address, the description, the facts in the app's order ("S4 E7",
  /// "15. September 2026", "41 Min", "★ 7.6") and the age rating drawn in a
  /// box of its own.
  final String? backdrop;
  final String? summary;
  final List<String> facts;
  final String? badge;

  /// The four corner colours Plex derives from the title's artwork, for a
  /// ground in its colours (the start page's "Hintergrund in Posterfarben").
  final UltraBlurColors? colours;

  Map<String, dynamic> toJson(String? Function(String? address) art) => {
    'id': id,
    'kind': kind,
    'title': title,
    'subtitle': ?subtitle,
    'image': ?art(image),
    'imageShape': ?imageShape?.name,
    'progress': ?progress,
    'startsAt': ?startsAt?.millisecondsSinceEpoch,
    'endsAt': ?endsAt?.millisecondsSinceEpoch,
    'live': ?live,
    if (home != null) 'home': home!.toJson(art),
    if (away != null) 'away': away!.toJson(art),
    'score': ?score,
    'backdrop': ?art(backdrop),
    'summary': ?summary,
    if (facts.isNotEmpty) 'facts': facts,
    'badge': ?badge,
    if (colours case final c?) 'colours': [_hex(c.topLeft), _hex(c.topRight), _hex(c.bottomRight), _hex(c.bottomLeft)],
    'open': open,
  };
}

/// A tile of a league's matchday, for a launcher's sport section: both clubs
/// with their crests and colours, the kickoff, and once it is on or over the
/// score as "Jetzt live" shows it. A tap opens the Sport page.
HomeRowTile homeRowTileForMatch(SportMatch match, {required DateTime now}) {
  final live = match.isLive(now);
  final score = live ? match.scoreAt(now) : (match.isFinished ? match.result : null);
  final kickoff = match.kickoff.toLocal();
  final locale = LocaleSettings.currentLocale.intlLocaleName;
  return HomeRowTile(
    id: 'match:${match.id}',
    kind: 'game',
    title: '${match.home.shortName} – ${match.away.shortName}',
    subtitle: live
        ? t.sport.live
        : match.isFinished
        ? t.sport.finalScore
        : '${DateFormat.E(locale).format(kickoff)} ${DateFormat('d.M.').format(kickoff)}',
    imageShape: HomeRowImageShape.logo,
    startsAt: match.kickoff,
    live: live,
    home: HomeRowTeam(name: match.home.name, image: match.home.iconUrl, colour: clubColourFor(match.home)),
    away: HomeRowTeam(name: match.away.name, image: match.away.iconUrl, colour: clubColourFor(match.away)),
    score: score == null ? null : '${score.home}:${score.away}',
    open: 'plebz://sport',
  );
}

/// "Spieltag 8 · 24.–26. Oktober": the matchday and the days it is played on.
String homeRowsMatchdayLine(int matchday, List<SportMatch> matches) {
  final label = t.sport.matchday(n: matchday);
  if (matches.isEmpty) return label;
  final locale = LocaleSettings.currentLocale.intlLocaleName;
  final days = [for (final match in matches) match.kickoff.toLocal()]..sort();
  final first = days.first, last = days.last;
  String range;
  if (first.year == last.year && first.month == last.month) {
    range = first.day == last.day
        ? DateFormat.MMMMd(locale).format(first)
        : '${first.day}.–${DateFormat.MMMMd(locale).format(last)}';
  } else {
    range = '${DateFormat.MMMd(locale).format(first)} – ${DateFormat.MMMd(locale).format(last)}';
  }
  return '$label · $range';
}

/// The id Continue Watching and the shelf links use for a title:
/// `plezy_<server>_<item>` — see `SystemShelfService.parseContentId`.
String homeRowsContentId(String serverId, String itemId) => 'plezy_${serverId}_$itemId';

/// A tile for a library title, or null when it has nothing to open.
///
/// [resume] makes it a Continue Watching tile: the picture the start page
/// shows for it ([posterMode], the episode's still in 16:9 by default), how
/// far it has been watched, a tap that plays on — or, with [openDetails] (the
/// start page's own choice for Continue Watching), opens the title's page —
/// and what the launcher's spotlight writes over it. Otherwise it is a poster
/// whose tap opens the title's page.
HomeRowTile? homeRowTileForItem(
  MediaItem item, {
  required MediaServerClient? client,
  bool resume = false,
  bool hideSpoilers = false,
  EpisodePosterMode posterMode = EpisodePosterMode.episodeThumbnail,
  bool openDetails = false,
  UltraBlurColors? colours,
}) {
  final serverId = item.serverId;
  final String open;
  if (serverId != null && client != null) {
    final contentId = Uri.encodeQueryComponent(homeRowsContentId(serverId, item.id));
    open = resume && !openDetails ? 'plebz://play?content_id=$contentId' : 'plebz://open?content_id=$contentId';
  } else if (!resume) {
    // A watchlist title no server has: the watchlist itself is the way to it.
    open = 'plebz://watchlist';
  } else {
    return null;
  }

  final spoiler = hideSpoilers && item.shouldHideSpoiler;
  final wide = resume && item.usesWideAspectRatio(posterMode, mixedHubContext: true);
  String? path;
  if (resume) {
    if (spoiler && wide) path = item.spoilerSafeArt;
    path ??= item.posterThumb(mode: posterMode, mixedHubContext: true);
  } else {
    path = item.posterThumb(mode: EpisodePosterMode.seasonPoster);
  }
  final image = _address(path, client, width: wide ? 640 : 400, height: wide ? 360 : 600);
  final backdropPath = !resume
      ? null
      : spoiler
      ? item.spoilerSafeArt
      : item.heroArtCandidates(containerAspectRatio: 16 / 9).firstOrNull ?? item.artPath;
  final backdrop = _address(backdropPath, client, width: 1280, height: 720);

  final episode = item.kind == MediaKind.episode && item.grandparentTitle != null;
  final duration = item.durationMs ?? 0;
  final offset = item.viewOffsetMs ?? 0;
  return HomeRowTile(
    id: serverId == null ? 'item:${item.id}' : homeRowsContentId(serverId, item.id),
    kind: item.kind.name,
    title: episode ? item.grandparentTitle! : (item.title ?? ''),
    subtitle: episode ? _episodeLine(item) : item.year?.toString(),
    image: image,
    imageShape: wide ? HomeRowImageShape.landscape : HomeRowImageShape.poster,
    progress: resume && duration > 0 && offset > 0 ? (offset / duration).clamp(0.0, 1.0) : null,
    open: open,
    backdrop: backdrop,
    summary: resume && !spoiler && (item.summary?.trim().isNotEmpty ?? false) ? item.summary!.trim() : null,
    facts: resume ? _spotlightFacts(item) : const [],
    badge: resume && item.contentRating != null ? formatContentRating(item.contentRating!) : null,
    colours: colours,
  );
}

/// The start page spotlight's facts, in its order: which episode, when, what
/// kind, how long, which cut, how it scored. The age rating goes apart, as
/// the box the spotlight draws it in.
List<String> _spotlightFacts(MediaItem item) {
  final episodeLabel = formatSeasonEpisodeLabel(item.parentIndex, item.index);
  final edition = item.editionTitle?.trim();
  return [
    if (item.isEpisode && episodeLabel != null) episodeLabel,
    if (item.isEpisode && item.originallyAvailableAt != null)
      formatFullDate(item.originallyAvailableAt!)
    else if (item.year != null)
      item.year.toString(),
    if (item.isMovie) t.discover.movie else if (item.isShow) t.discover.tvShow,
    if (item.hasRuntime) formatDurationTextual(item.durationMs!),
    if (edition != null && edition.isNotEmpty) edition,
    for (final rating in mediaRatingsFor(item).take(2)) '★ ${mediaRatingLabel(rating)}',
  ];
}

/// A tile of "Jetzt live": a game with both crests, or a favourite channel
/// with what is on it. A tap does what the tile in the app does.
HomeRowTile homeRowTileForLiveNow(
  LiveNowEntry entry, {
  required MediaServerClient? Function(String serverId) clientFor,
  required DateTime now,
}) {
  final open = 'plebz://now?id=${Uri.encodeQueryComponent(entry.id)}';
  switch (entry) {
    case LiveNowGame(:final match, :final league):
      final live = match.isLive(now);
      final score = live ? match.scoreAt(now) : (match.isFinished ? match.result : null);
      return HomeRowTile(
        id: entry.id,
        kind: 'game',
        title: '${match.home.shortName} – ${match.away.shortName}',
        subtitle: [liveNowLeagueName(league), liveNowGameStatus(match, now)].join(' · '),
        imageShape: HomeRowImageShape.logo,
        startsAt: match.kickoff,
        live: live,
        home: HomeRowTeam(name: match.home.name, image: match.home.iconUrl, colour: clubColourFor(match.home)),
        away: HomeRowTeam(name: match.away.name, image: match.away.iconUrl, colour: clubColourFor(match.away)),
        score: score == null ? null : '${score.home}:${score.away}',
        open: open,
      );
    case LiveNowChannel(:final channel, :final program):
      final begins = program?.beginsAt;
      final ends = program?.endsAt;
      final seconds = now.millisecondsSinceEpoch ~/ 1000;
      return HomeRowTile(
        id: entry.id,
        kind: 'channel',
        title: program?.title ?? channel.displayName,
        subtitle: channel.displayName,
        image: _channelLogo(channel, clientFor),
        imageShape: HomeRowImageShape.logo,
        startsAt: begins == null ? null : DateTime.fromMillisecondsSinceEpoch(begins * 1000),
        endsAt: ends == null ? null : DateTime.fromMillisecondsSinceEpoch(ends * 1000),
        progress: begins != null && ends != null && ends > begins
            ? ((seconds - begins) / (ends - begins)).clamp(0.0, 1.0)
            : null,
        live: true,
        open: open,
      );
  }
}

String? _episodeLine(MediaItem item) {
  final season = item.parentIndex;
  final episode = item.index;
  final code = season != null && episode != null ? 'S$season E$episode' : null;
  return [?code, ?item.title].join(' · ');
}

String? _channelLogo(LiveTvChannel channel, MediaServerClient? Function(String serverId) clientFor) {
  final serverId = channel.serverId;
  final client = serverId == null ? null : clientFor(serverId);
  for (final logo in [channel.thumb, channel.guideLogo]) {
    final address = _address(logo?.trim(), client, width: 400, height: 400);
    if (address != null) return address;
  }
  return null;
}

/// [path] as an address the app can fetch: as it is when it is one already,
/// through [client] when it is a server's path, null otherwise.
String? _address(String? path, MediaServerClient? client, {required int width, required int height}) {
  if (path == null || path.isEmpty) return null;
  if (MediaImageHelper.isSelfContainedImageUrl(path)) return path;
  if (client == null) return null;
  final address = client.thumbnailUrl(path, width: width, height: height);
  return address.isEmpty ? null : address;
}
