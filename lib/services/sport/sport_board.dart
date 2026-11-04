import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateUtils;

import 'club_colours.dart';
import 'sport_models.dart';

/// Why a game stands on the Sport page's stage (Plebz).
enum SportStageReason {
  /// It is being played now — the favourite club's first.
  live,

  /// The favourite club plays it, before kickoff or after the whistle.
  favourite,

  /// A European cup's game with a German club in it.
  germanClub,

  /// The next game of the matchday to kick off.
  next,

  /// Every game is over: the first of them.
  finished,
}

/// The game a matchday puts on its stage, and why (Plebz, the user's order,
/// 2026-11-03): a game being played now, the favourite club's first; else the
/// favourite club's game; in a European cup a game with a German club in it;
/// else the next game to kick off; and with every game over, the first.
/// Null without games.
({SportMatch match, SportStageReason reason})? sportStageFor(
  List<SportMatch> matches, {
  required SportLeague league,
  required int favouriteClub,
  required DateTime now,
}) {
  if (matches.isEmpty) return null;
  bool favourite(SportMatch match) =>
      favouriteClub != 0 && (match.home.id == favouriteClub || match.away.id == favouriteClub);

  // A European cup's game with a German club, which a German viewer follows
  // before the rest (Plebz).
  bool german(SportMatch match) => league.isEuropean && (isGermanClub(match.home) || isGermanClub(match.away));

  final live = matches.where((match) => match.isLive(now)).toList();
  if (live.isNotEmpty) {
    return (match: live.firstWhereOrNull(favourite) ?? live.firstWhereOrNull(german) ?? live.first, reason: .live);
  }

  final own = matches.where(favourite).firstOrNull;
  if (own != null) return (match: own, reason: .favourite);

  final upcoming = matches.where((match) => !match.isFinished && match.kickoff.isAfter(now)).toList();
  final germanNext = upcoming.firstWhereOrNull(german);
  if (germanNext != null) return (match: germanNext, reason: .germanClub);
  if (upcoming.isNotEmpty) return (match: upcoming.first, reason: .next);
  return (match: matches.first, reason: .finished);
}

/// What a row of the Sport page holds (Plebz).
enum SportBoardRowKind {
  /// A European cup's games with German clubs, ahead of the rest.
  germanClubs,

  /// The games of one day.
  day,

  /// The games of one kickoff on a day with several — a cup's evening.
  kickoff,
}

/// One row of the Sport page: its games, and what names it.
@immutable
class SportBoardRow {
  const SportBoardRow({required this.kind, required this.day, this.kickoff, required this.matches});

  final SportBoardRowKind kind;

  /// The day it is played on; the first game's for [SportBoardRowKind.germanClubs].
  final DateTime day;

  /// The kickoff it gathers, for [SportBoardRowKind.kickoff].
  final DateTime? kickoff;

  final List<SportMatch> matches;

  /// Whether the row before it was on the same day: its name then leaves the
  /// date out ("Dienstag · 21:00").
  bool sameDayAs(SportBoardRow? previous) =>
      previous != null && previous.kind != SportBoardRowKind.germanClubs && DateUtils.isSameDay(previous.day, day);
}

/// A matchday as the Sport page's rows (Plebz): a league's by day; a cup's
/// by kickoff wherever a day has more than one — a Champions League evening
/// is nine games at two times — with a European cup's German clubs in a row
/// of their own ahead of the rest. [matches] in kickoff order.
List<SportBoardRow> sportBoardRows(List<SportMatch> matches, {required SportLeague league}) {
  if (matches.isEmpty) return const [];
  final byDay = <DateTime, List<SportMatch>>{};
  for (final match in matches) {
    (byDay[DateUtils.dateOnly(match.kickoff.toLocal())] ??= []).add(match);
  }
  final rows = <SportBoardRow>[];
  if (league.isEuropean) {
    final german = [
      for (final match in matches)
        if (isGermanClub(match.home) || isGermanClub(match.away)) match,
    ];
    if (german.isNotEmpty) {
      rows.add(
        SportBoardRow(kind: .germanClubs, day: DateUtils.dateOnly(german.first.kickoff.toLocal()), matches: german),
      );
    }
  }
  for (final MapEntry(key: day, value: games) in byDay.entries) {
    final kickoffs = {for (final match in games) match.kickoff.toLocal()};
    if (league.isDomestic || kickoffs.length < 2) {
      rows.add(SportBoardRow(kind: .day, day: day, matches: games));
      continue;
    }
    for (final kickoff in kickoffs) {
      rows.add(
        SportBoardRow(
          kind: .kickoff,
          day: day,
          kickoff: kickoff,
          matches: [
            for (final match in games)
              if (match.kickoff.toLocal() == kickoff) match,
          ],
        ),
      );
    }
  }
  return rows;
}
