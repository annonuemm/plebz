import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'openligadb_client.dart';
import 'sport_models.dart';

/// What a league looks like right now: which season, which matchday is the
/// current one (see [SportRepository.current]), and that matchday's fixtures.
class SportLeagueNow {
  final int season;
  final int matchday;
  final List<SportMatch> matches;

  const SportLeagueNow({required this.season, required this.matchday, required this.matches});
}

/// The Sport destination's memory of what it has fetched.
///
/// A matchday is asked for every time the viewer steps to it, and the table
/// every time a league opens; without this each of those is a round trip to a
/// server someone else pays for. How long an answer is kept depends on how
/// fast it can change: a finished matchday is history, one being played
/// changes by the minute.
///
/// A failed fetch hands back what was kept before, however old — a table from
/// ten minutes ago is more use than an error — and only answers null when
/// there was never anything.
class SportRepository {
  SportRepository({OpenLigaDbClient? client}) : _client = client ?? OpenLigaDbClient();

  static final SportRepository instance = SportRepository();

  final OpenLigaDbClient _client;
  final Map<String, _Cached<Object>> _cache = {};
  final Map<String, Future<Object?>> _inFlight = {};

  static const _currentTtl = Duration(minutes: 1);
  static const _tableTtl = Duration(minutes: 2);
  static const _matchdaysTtl = Duration(hours: 12);
  static const _liveMatchdayTtl = Duration(minutes: 1);
  static const _upcomingMatchdayTtl = Duration(minutes: 15);
  static const _finishedMatchdayTtl = Duration(hours: 6);

  /// Friday to Monday, with a day to spare.
  static const _matchdaySpan = Duration(days: 5);

  /// The matchday a league opens on, and the one marked current.
  ///
  /// The provider's own "current" matchday stays on a finished one for days —
  /// it moves on roughly halfway to the next, which across an international
  /// break is the better part of two weeks. So once every game of it is over,
  /// from the Tuesday after its last one the next matchday is the current
  /// one instead: the weekend's results have had their Sunday and Monday, and
  /// what is wanted by midweek is what comes next. See [movesOnAt].
  Future<SportLeagueNow?> current(SportLeague league) => _cached<SportLeagueNow>(
    'now:${league.shortcut}',
    ttl: (_) => _currentTtl,
    fetch: () async {
      final currentAnswer = await _client.fetchCurrentMatchday(league);
      if (currentAnswer == null || currentAnswer.isEmpty) return null;
      final season = currentAnswer.first.season;
      final order = currentAnswer.first.matchday.order;
      // The provider keeps its "current" answer for hours on its own side —
      // on a Saturday evening it still had the afternoon's games at the fifth
      // minute. It is good for which matchday it is; the scores come from the
      // matchday asked for by number, which is up to date.
      final numbered = await matchday(league, season, order);
      final matches = numbered == null || numbered.isEmpty ? currentAnswer : numbered;

      // Only when a game is still to come well after the rest does it matter
      // when the next matchday starts — and only then is it asked for early.
      List<SportMatch>? next;
      if (hasLateGame(matches)) next = await matchday(league, season, order + 1);
      final nextStarts = next == null || next.isEmpty ? null : _firstKickoff(next);

      final movesOn = movesOnAt(matches, nextStarts: nextStarts);
      if (movesOn != null && !clock.now().isBefore(movesOn)) {
        next ??= await matchday(league, season, order + 1);
        // Past the last matchday of the season there is no next one, and the
        // last stays current until the provider starts the new season.
        if (next != null && next.isNotEmpty) {
          return SportLeagueNow(season: season, matchday: order + 1, matches: next);
        }
      }
      return SportLeagueNow(season: season, matchday: order, matches: matches);
    },
  );

  /// When a matchday stops being the current one: the start of the first
  /// Tuesday after the day of its last game — or null while a game of it is
  /// still to be played or being played.
  ///
  /// A game counts as over once the provider says so, or once it is three
  /// hours past kickoff without having said so (see [SportMatch.isLive]).
  ///
  /// A game still to come holds its matchday — a Friday game five days after
  /// the rest is the next game there is, and the matchday it belongs to is
  /// the one to show until it has been played. Only a game that kicks off
  /// after [nextStarts], the first kickoff of the following matchday, does
  /// not: that is a Nachholspiel, made up weeks later, and waiting for it
  /// would keep a long-finished matchday current until then.
  ///
  /// Local time, since "Tuesday" is the viewer's.
  static DateTime? movesOnAt(List<SportMatch> matches, {DateTime? nextStarts}) {
    final now = clock.now();
    DateTime? last;
    for (final match in matches) {
      final over = match.isFinished || (!now.isBefore(match.kickoff) && !match.isLive(now));
      if (!over) {
        if (nextStarts != null && !match.kickoff.isBefore(nextStarts)) continue;
        return null;
      }
      if (last == null || match.kickoff.isAfter(last)) last = match.kickoff;
    }
    if (last == null) return null;
    var day = DateTime(last.year, last.month, last.day + 1);
    while (day.weekday != DateTime.tuesday) {
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return day;
  }

  /// Whether a game of the matchday is still to come more than
  /// [_matchdaySpan] after its first kickoff — the one case where whether it
  /// is a Nachholspiel decides anything.
  static bool hasLateGame(List<SportMatch> matches) {
    if (matches.isEmpty) return false;
    final first = _firstKickoff(matches);
    return matches.any((match) => !match.isFinished && match.kickoff.difference(first) > _matchdaySpan);
  }

  static DateTime _firstKickoff(List<SportMatch> matches) =>
      matches.map((match) => match.kickoff).reduce((a, b) => a.isBefore(b) ? a : b);

  Future<List<SportMatchday>?> matchdays(SportLeague league, int season) => _cached<List<SportMatchday>>(
    'days:${league.shortcut}:$season',
    ttl: (_) => _matchdaysTtl,
    fetch: () => _client.fetchMatchdays(league, season: season),
  );

  Future<List<SportMatch>?> matchday(SportLeague league, int season, int matchday) => _cached<List<SportMatch>>(
    'day:${league.shortcut}:$season:$matchday',
    ttl: _matchdayTtl,
    fetch: () => _client.fetchMatchday(league, season: season, matchday: matchday),
  );

  Future<List<SportTableRow>?> table(SportLeague league, int season) => _cached<List<SportTableRow>>(
    'table:${league.shortcut}:$season',
    ttl: (_) => _tableTtl,
    fetch: () => _client.fetchTable(league, season: season),
  );

  /// Forget everything about [league], so the next ask goes to the network.
  /// What a manual refresh is for; the answers themselves stay available as a
  /// fallback until a fresh one replaces them.
  void invalidate(SportLeague league) {
    final marker = ':${league.shortcut}';
    for (final entry in _cache.entries) {
      if (entry.key.contains(marker)) entry.value.expire();
    }
  }

  @visibleForTesting
  void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  static Duration _matchdayTtl(List<SportMatch> matches) {
    final now = clock.now();
    if (matches.every((match) => match.isFinished)) return _finishedMatchdayTtl;
    if (matches.any((match) => match.isLive(now))) return _liveMatchdayTtl;
    return _upcomingMatchdayTtl;
  }

  Future<T?> _cached<T extends Object>(
    String key, {
    required Duration Function(T value) ttl,
    required Future<T?> Function() fetch,
  }) async {
    final kept = _cache[key];
    if (kept != null && !kept.isStale) return kept.value as T;

    // A block body, not an arrow: `remove` hands back the very future this
    // callback is attached to, and `whenComplete` waits for a future its
    // callback returns — an arrow here makes every fetch wait on itself.
    final pending = _inFlight[key] ??= fetch().whenComplete(() {
      _inFlight.remove(key);
    });
    final fresh = await pending as T?;
    if (fresh != null) {
      _cache[key] = _Cached<Object>(fresh, clock.now().add(ttl(fresh)));
      return fresh;
    }
    return kept?.value as T?;
  }
}

class _Cached<T> {
  _Cached(this.value, this._expiresAt);

  final T value;
  DateTime _expiresAt;

  bool get isStale => !clock.now().isBefore(_expiresAt);

  void expire() => _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
}
