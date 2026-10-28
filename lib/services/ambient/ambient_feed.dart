import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../i18n/app_locale_utils.dart';
import '../../i18n/strings.g.dart';
import '../../utils/app_logger.dart';
import '../home_rows.dart';
import '../program_reminders.dart';

/// What the paused player hands the screensaver (Plebz): enough to show the
/// title and to play on with OK.
@immutable
class AmbientPause {
  const AmbientPause({required this.title, this.subtitle, this.remaining, this.image});

  final String title;

  /// The episode ("S2 E4 · Hello, Ms. Cobel"), or nothing for a film.
  final String? subtitle;

  /// Already worded: "noch 1 Std. 12 Min.".
  final String? remaining;

  /// The picture's address. It may carry a server's credentials, so it only
  /// ever goes to the screensaver in the same process, never to a file.
  final String? image;

  @override
  bool operator ==(Object other) =>
      other is AmbientPause &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.remaining == remaining &&
      other.image == image;

  @override
  int get hashCode => Object.hash(title, subtitle, remaining, image);
}

/// The screensaver's material (Plebz): Android's own screensaver slot, filled
/// by `PlebzAmbientDream` on the Android side.
///
/// It reads the start page's rows as [HomeRows] keeps them for a launcher –
/// Continue Watching, the library shelves, the watchlist, the
/// recommendations, "Jetzt live" and the leagues – and the guide's reminders,
/// and writes them as ready-worded scenes: the screensaver draws, it does not
/// decide. Pictures go over as keys, as for the launcher: their addresses
/// carry server credentials and stay in the app, which fetches them itself.
///
/// The paused player's title travels apart ([setPaused]), in memory only.
/// Android only; elsewhere every call does nothing.
class AmbientFeed {
  AmbientFeed({
    this.channel = const MethodChannel('app.plebz/ambient'),
    HomeRows? rows,
    this.reminderChanges,
    this.reminderSource,
    bool? supported,
    this.debounce = const Duration(seconds: 2),
  }) : rows = rows ?? HomeRows.instance,
       _supported = supported ?? (!kIsWeb && Platform.isAndroid);

  static final AmbientFeed instance = AmbientFeed();

  static const int schema = 1;

  /// How long a "Neu seit gestern" scene stays true when the app is not
  /// opened again to write a newer one.
  static const Duration newValidFor = Duration(hours: 24);

  /// A game's end where the row does not say: room for a cup tie's extra
  /// time and penalties.
  static const Duration gameLength = Duration(minutes: 150);

  static const int maxContinue = 6;
  static const int maxLibrary = 24;
  static const int maxGames = 6;
  static const int maxChannels = 4;
  static const int maxReminders = 6;
  static const int maxTicker = 4;

  final MethodChannel channel;
  final HomeRows rows;

  /// The guide's reminders and what tells of a change to them; the app's own
  /// unless a test hands others in.
  final Listenable? reminderChanges;
  final List<ProgramReminder> Function()? reminderSource;
  final bool _supported;
  final Duration debounce;

  bool _started = false;
  bool _handlerSet = false;
  Timer? _timer;
  String? _lastContent;
  AmbientPause? _pause;
  Future<void> Function()? _onResume;
  Future<bool>? _settingsAvailable;

  bool get supported => _supported;

  /// Told when a key has ended the app's own screensaver ([AmbientInApp]).
  VoidCallback? onInAppClosed;

  Listenable get _reminderListenable => reminderChanges ?? ProgramReminders.instance;
  List<ProgramReminder> _reminderEntries() => (reminderSource ?? () => ProgramReminders.instance.entries)();

  /// Starts following the rows and the reminders; safe to call again.
  void start() {
    if (!_supported || _started) return;
    _started = true;
    _ensureHandler();
    rows.addListener(_schedule);
    _reminderListenable.addListener(_schedule);
    if (reminderSource == null) unawaited(ProgramReminders.instance.ensureLoaded());
    _schedule();
  }

  void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    channel.setMethodCallHandler(_onCall);
  }

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'resume':
        final resume = _onResume;
        if (resume == null) return false;
        await resume();
        return true;
      case 'inAppClosed':
        onInAppClosed?.call();
        return true;
    }
    throw MissingPluginException('${call.method} is not an ambient method');
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(flush()));
  }

  /// Writes the scenes, when they changed since the last write.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (!_supported) return;
    final payload = buildPayload();
    if (payload.content == _lastContent) return;
    try {
      final ok = await channel.invokeMethod<bool>('publish', {
        'snapshot': payload.snapshot,
        'sources': payload.sources,
      });
      if (ok == true) _lastContent = payload.content;
    } catch (e) {
      appLogger.d('Ambient: publish failed', error: e);
    }
  }

  /// The paused title for the screensaver's first scene, or null once it plays
  /// again or the player is gone. [onResume] is what OK there does.
  void setPaused(AmbientPause? pause, {Future<void> Function()? onResume}) {
    if (!_supported) return;
    _ensureHandler();
    _onResume = pause == null ? null : onResume;
    if (pause == _pause) return;
    _pause = pause;
    final map = pause == null
        ? null
        : <String, Object?>{
            'kicker': t.ambient.paused,
            'title': pause.title,
            'subtitle': pause.subtitle,
            'remaining': pause.remaining,
            'hint': t.ambient.okResumes,
            'image': pause.image,
          };
    channel.invokeMethod<bool>('setPaused', map).catchError((Object e) {
      appLogger.d('Ambient: pause hand-over failed', error: e);
      return false;
    });
  }

  /// Whether this device has Android's screensaver settings to send the viewer
  /// to (a Google TV may not).
  Future<bool> settingsAvailable() => _settingsAvailable ??= () async {
    if (!_supported) return false;
    try {
      return await channel.invokeMethod<bool>('canOpenSettings') ?? false;
    } catch (_) {
      return false;
    }
  }();

  /// Opens Android's screensaver settings, where Plebz is chosen.
  Future<bool> openSettings() async {
    if (!_supported) return false;
    try {
      return await channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (e) {
      appLogger.d('Ambient: settings unavailable', error: e);
      return false;
    }
  }

  /// Lays the app's own screensaver over the app; whether it shows.
  Future<bool> showInApp() => _invokeInApp('showInApp');

  /// Takes the app's own screensaver away again (input it could not see).
  Future<bool> hideInApp() => _invokeInApp('hideInApp');

  /// Keeps the device's screensaver from starting over the app, so the app's
  /// own can at the viewer's time.
  Future<bool> setKeepAwake(bool on) => _invokeInApp('setKeepAwake', {'on': on});

  Future<bool> _invokeInApp(String method, [Object? arguments]) async {
    if (!_supported) return false;
    _ensureHandler();
    try {
      return await channel.invokeMethod<bool>(method, arguments) ?? false;
    } catch (e) {
      appLogger.d('Ambient: $method failed', error: e);
      return false;
    }
  }

  /// The snapshot as it would be written, the picture addresses by key, and
  /// [content]: the snapshot without its time, which says whether anything
  /// changed since the last write.
  @visibleForTesting
  ({String snapshot, Map<String, String> sources, String content}) buildPayload({DateTime? now}) {
    now ??= clock.now();
    final sources = <String, String>{};
    String? art(String? address) {
      if (address == null || address.isEmpty) return null;
      final key = sha1.convert(utf8.encode(address)).toString();
      sources[key] = address;
      return key;
    }

    final locale = LocaleSettings.currentLocale.intlLocaleName;
    String clockTime(DateTime at) => DateFormat.Hm(locale).format(at.toLocal());
    bool today(DateTime at) {
      final local = at.toLocal(), here = now!.toLocal();
      return local.year == here.year && local.month == here.month && local.day == here.day;
    }

    final all = rows.rows;
    final scenes = <Map<String, Object?>>[];
    final ticker = <({DateTime? at, Map<String, Object?> entry})>[];
    final seen = <String>{};

    // Continue Watching: the title one is in the middle of.
    for (final row in all.where((row) => row.id == HomeRows.continueRow)) {
      for (final tile in row.tiles.take(maxContinue)) {
        final image = art(tile.ambientImage ?? tile.backdrop);
        if (image == null) continue;
        seen.add(tile.id);
        scenes.add({
          'kind': 'continue',
          'kicker': t.ambient.continueWatching,
          'title': tile.title,
          'subtitle': ?_line(tile.facts.isNotEmpty ? tile.facts.take(3) : [?tile.subtitle]),
          'image': image,
          'progress': ?tile.progress,
          'open': tile.open,
        });
      }
    }

    // The library, the watchlist and the recommendations: one title at a time.
    var library = 0;
    for (final row in all) {
      final String kicker;
      if (row.id == HomeRows.watchlistRow) {
        kicker = t.ambient.fromWatchlist;
      } else if (row.id == HomeRows.recommendationsRow) {
        kicker = row.title;
      } else if (row.id.startsWith(HomeRows.libraryRowPrefix)) {
        kicker = t.ambient.fromLibrary;
      } else {
        continue;
      }
      for (final tile in row.tiles) {
        if (library >= maxLibrary) break;
        final image = art(tile.ambientImage);
        if (image == null || !seen.add(tile.id)) continue;
        library++;
        scenes.add({
          'kind': 'library',
          'kicker': kicker,
          'title': tile.title,
          'subtitle': ?tile.subtitle,
          'image': image,
          'open': tile.open,
        });
      }
    }

    // What came into the libraries since yesterday began: films by number,
    // series by how many have something new.
    final here = now.toLocal();
    final since = DateTime(here.year, here.month, here.day - 1);
    final fresh = <String, HomeRowTile>{};
    for (final row in all.where((row) => row.id.startsWith(HomeRows.libraryRowPrefix))) {
      for (final tile in row.tiles) {
        final added = tile.addedAt;
        if (added == null || added.isAfter(now) || added.isBefore(since)) continue;
        if (!const {'movie', 'show', 'season', 'episode'}.contains(tile.kind)) continue;
        fresh.putIfAbsent(tile.id, () => tile);
      }
    }
    if (fresh.isNotEmpty) {
      final movies = fresh.values.where((tile) => tile.kind == 'movie').length;
      final series = {
        for (final tile in fresh.values)
          if (tile.kind != 'movie') tile.title,
      }.length;
      final count = [
        if (movies > 0) t.ambient.newMovies(n: movies),
        if (series > 0) t.ambient.newSeries(n: series),
      ].join(', ');
      scenes.add({
        'kind': 'new',
        'kicker': t.ambient.newSinceYesterday,
        'title': count,
        'subtitle': ?_line({for (final tile in fresh.values) tile.title}.take(4)),
        'posters': [for (final tile in fresh.values.take(6)) ?art(tile.image)],
        'validUntil': now.add(newValidFor).millisecondsSinceEpoch,
      });
      ticker.add((at: null, entry: {'text': '${t.ambient.newSinceYesterday}: $count'}));
    }

    // Today's games: "Jetzt live"'s, else the favourite club's league.
    var games = [
      for (final row in all.where((row) => row.id == HomeRows.liveNowRow))
        for (final tile in row.tiles)
          if (tile.kind == 'game') tile,
    ];
    if (games.isEmpty) {
      final league = all.where((row) => row.id.startsWith('sport:')).toList();
      final chosen = league.where((row) => row.selected).firstOrNull ?? league.firstOrNull;
      games = [...?chosen?.tiles];
    }
    games = [
      for (final tile in games)
        if (tile.live == true || (tile.startsAt != null && today(tile.startsAt!))) tile,
    ];
    for (final tile in games.take(maxGames)) {
      final starts = tile.startsAt;
      final ends = tile.endsAt ?? starts?.add(gameLength);
      scenes.add({
        'kind': 'sport',
        'kicker': t.ambient.sportToday,
        'title': tile.title,
        'subtitle': ?_line([if (starts != null && tile.live != true) clockTime(starts), ?tile.subtitle]),
        'home': ?_team(tile.home, art),
        'away': ?_team(tile.away, art),
        'score': ?tile.score,
        'live': tile.live == true,
        'startsAt': ?starts?.millisecondsSinceEpoch,
        'endsAt': ?ends?.millisecondsSinceEpoch,
        'open': tile.open,
      });
      ticker.add((
        at: starts,
        entry: {
          if (starts != null && tile.live != true) 'time': clockTime(starts),
          'text': tile.title,
          if (tile.live == true) 'live': true,
          'startsAt': ?starts?.millisecondsSinceEpoch,
          'endsAt': ?ends?.millisecondsSinceEpoch,
        },
      ));
    }

    // The guide: reminders set for today, then what runs on the favourites.
    for (final reminder in _reminderEntries()) {
      if (scenes.where((scene) => scene['kind'] == 'tv').length >= maxReminders) break;
      if (!today(reminder.startsAt) || !reminder.endsAtTime.isAfter(now)) continue;
      final time = clockTime(reminder.startsAt);
      scenes.add({
        'kind': 'tv',
        'kicker': t.ambient.reminderSet,
        'title': reminder.title,
        'subtitle': _line([time, reminder.channelTitle]),
        'startsAt': reminder.startsAt.millisecondsSinceEpoch,
        'endsAt': reminder.endsAtTime.millisecondsSinceEpoch,
        'open': 'plebz://reminder?key=${Uri.encodeQueryComponent(reminder.key)}',
      });
      ticker.add((
        at: reminder.startsAt,
        entry: {
          'time': time,
          'text': _line([reminder.title, reminder.channelTitle]),
          'startsAt': reminder.startsAt.millisecondsSinceEpoch,
          'endsAt': reminder.endsAtTime.millisecondsSinceEpoch,
        },
      ));
    }
    final channels = [
      for (final row in all.where((row) => row.id == HomeRows.liveNowRow))
        for (final tile in row.tiles)
          if (tile.kind == 'channel' && tile.endsAt != null && tile.endsAt!.isAfter(now)) tile,
    ];
    for (final tile in channels.take(maxChannels)) {
      scenes.add({
        'kind': 'tv',
        'kicker': t.ambient.onNow,
        'title': tile.title,
        'subtitle': ?tile.subtitle,
        'logo': ?art(tile.image),
        'progress': ?tile.progress,
        'startsAt': ?tile.startsAt?.millisecondsSinceEpoch,
        'endsAt': tile.endsAt!.millisecondsSinceEpoch,
        'open': tile.open,
      });
    }

    ticker.sort((a, b) {
      final at = a.at, bt = b.at;
      if (at == null) return bt == null ? 0 : 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });

    final body = <String, dynamic>{
      'theme': ?rows.theme?.toJson(),
      'labels': {'live': t.sport.live},
      // The app's language, for the date the screensaver writes itself.
      'locale': LocaleSettings.currentLocale.languageTag,
      'scenes': scenes,
      'ticker': [for (final item in ticker.take(maxTicker)) item.entry],
    };
    final content = jsonEncode(body);
    final snapshot = jsonEncode({'schema': schema, 'updatedAt': now.millisecondsSinceEpoch, ...body});
    return (snapshot: snapshot, sources: sources, content: content);
  }

  static String? _line(Iterable<String> parts) {
    final kept = [
      for (final part in parts)
        if (part.trim().isNotEmpty) part.trim(),
    ];
    return kept.isEmpty ? null : kept.join(' · ');
  }

  static Map<String, Object?>? _team(HomeRowTeam? team, String? Function(String?) art) {
    if (team == null) return null;
    final colour = team.colour;
    return {
      'name': team.name,
      'image': ?art(team.image),
      if (colour != null)
        'colour': '#${(colour.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
    };
  }

  @visibleForTesting
  void debugReset() {
    _timer?.cancel();
    _timer = null;
    _lastContent = null;
    _pause = null;
    _onResume = null;
    _settingsAvailable = null;
    onInAppClosed = null;
    if (_started) {
      rows.removeListener(_schedule);
      _reminderListenable.removeListener(_schedule);
      _started = false;
    }
  }
}
