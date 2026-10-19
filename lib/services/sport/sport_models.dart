/// The competitions the Sport destination can follow, in their default order.
///
/// [shortcut] is OpenLigaDB's name for the competition — the one part of every
/// URL that changes between them. The three German leagues are on by default;
/// the European cups and the DFB-Pokal are switched on under "Ligen verwalten"
/// ([SportLeagueLayout]).
enum SportLeague {
  bundesliga1('bl1'),
  bundesliga2('bl2'),
  liga3('bl3'),
  championsLeague('ucl'),

  /// OpenLigaDB names the Europa League after its season — `uel` was
  /// 2025/26's, abandoned in its knock-out rounds; `uel2026` is 2026/27's.
  /// The next season needs the next name.
  europaLeague('uel2026'),
  dfbPokal('dfb');

  const SportLeague(this.shortcut);

  final String shortcut;

  /// A German league, where every club plays every other: numbered matchdays,
  /// a table with promotion and relegation, and the clubs a favourite is
  /// chosen from.
  bool get isDomestic => switch (this) {
    bundesliga1 || bundesliga2 || liga3 => true,
    championsLeague || europaLeague || dfbPokal => false,
  };

  /// Whether the competition has a table: the cup is knock-out only.
  bool get hasTable => this != dfbPokal;

  /// Shown unless the viewer hides it.
  bool get shownByDefault => isDomestic;

  static SportLeague? fromShortcut(String shortcut) {
    for (final league in values) {
      if (league.shortcut == shortcut) return league;
    }
    return null;
  }
}

/// Which competitions the Sport destination shows, and in which order — what
/// "Ligen verwalten" arranges. Stored as the order of every competition's
/// shortcut and the set that is hidden; a competition the stored order does
/// not know yet (a newer app) goes to the end, shown or hidden by its default.
class SportLeagueLayout {
  const SportLeagueLayout({required this.order, required this.hidden});

  /// Every competition, in the viewer's order.
  final List<SportLeague> order;
  final Set<SportLeague> hidden;

  static final SportLeagueLayout standard = SportLeagueLayout.decode('');

  /// The ones on show, in order. Never empty: the last one cannot be hidden
  /// ([withHidden]), and a stored layout that hides everything shows the first.
  List<SportLeague> get visible {
    final shown = [
      for (final league in order)
        if (!hidden.contains(league)) league,
    ];
    return shown.isEmpty ? [order.first] : shown;
  }

  bool isHidden(SportLeague league) => !visible.contains(league);

  SportLeagueLayout withOrder(List<SportLeague> order) =>
      SportLeagueLayout(order: List.unmodifiable(order), hidden: hidden);

  /// [league] hidden or shown; hiding the last one on show is refused.
  SportLeagueLayout withHidden(SportLeague league, bool hide) {
    if (hide && visible.length == 1 && visible.single == league) return this;
    final next = {...hidden};
    hide ? next.add(league) : next.remove(league);
    return SportLeagueLayout(order: order, hidden: Set.unmodifiable(next));
  }

  /// `bl1,bl2,-ucl,…` — the order, a minus before each hidden one.
  String encode() => [for (final league in order) '${hidden.contains(league) ? '-' : ''}${league.shortcut}'].join(',');

  static SportLeagueLayout decode(String stored) {
    final order = <SportLeague>[];
    final hidden = <SportLeague>{};
    final known = <SportLeague>{};
    for (final raw in stored.split(',')) {
      final entry = raw.trim();
      if (entry.isEmpty) continue;
      final hide = entry.startsWith('-');
      final league = SportLeague.fromShortcut(hide ? entry.substring(1) : entry);
      if (league == null || !known.add(league)) continue;
      order.add(league);
      if (hide) hidden.add(league);
    }
    for (final league in SportLeague.values) {
      if (known.contains(league)) continue;
      order.add(league);
      if (!league.shownByDefault) hidden.add(league);
    }
    return SportLeagueLayout(order: List.unmodifiable(order), hidden: Set.unmodifiable(hidden));
  }
}

/// A club as a fixture or a table row names it.
class SportTeam {
  final int id;
  final String name;

  /// What the club is called in a narrow column — "Bayern", "Verl".
  final String shortName;

  /// A crest, loadable as it stands — see [crestUrl]. Null where the
  /// provider has none.
  final String? iconUrl;

  const SportTeam({required this.id, required this.name, required this.shortName, this.iconUrl});

  static SportTeam? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['teamId'] ?? raw['teamInfoId'];
    final name = raw['teamName'];
    if (id is! int || name is! String || name.isEmpty) return null;
    final shortName = raw['shortName'];
    final icon = raw['teamIconUrl'];
    return SportTeam(
      id: id,
      name: name,
      shortName: shortName is String && shortName.isNotEmpty ? shortName : name,
      iconUrl: icon is String && icon.isNotEmpty ? crestUrl(icon) : null,
    );
  }
}

/// The width every Wikimedia crest is asked for.
///
/// One of Wikimedia's standard thumbnail steps: any other width is refused
/// (100px answers 400; 120, 250, 330, 500 and 960 are served). 250 covers the
/// largest crest on screen — the match window's — at a television's density,
/// at a tenth of what the provider's own 960px links weigh.
const crestThumbnailWidth = 250;

/// [url] as something the app can draw.
///
/// About half the clubs' crests are Wikimedia originals in SVG, which the
/// image decoder cannot read, and the rest are Wikimedia thumbnails at
/// whatever width someone once pasted, or originals several hundred
/// kilobytes large. Wikimedia renders any of its files as a PNG thumbnail
/// from a URL built out of the original's, so every Wikimedia link — original
/// or thumbnail, `commons` or a language wiki — is rewritten to that
/// thumbnail at [crestThumbnailWidth]. A raster original smaller than that
/// comes back at its own size, not as an error.
///
/// Anything not on upload.wikimedia.org (imgur, the DFB) is left alone.
String crestUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host != 'upload.wikimedia.org') return url;
  final segments = uri.pathSegments;
  if (segments.length < 5 || segments[0] != 'wikipedia') return url;

  final List<String> path;
  if (segments[2] == 'thumb' && segments.length == 7) {
    // wikipedia/<wiki>/thumb/a/ab/<file>/<N>px-<name>
    final name = segments[6];
    final marker = name.indexOf('px-');
    if (marker < 0) return url;
    path = [...segments.take(6), '${crestThumbnailWidth}px-${name.substring(marker + 3)}'];
  } else if (segments.length == 5) {
    // wikipedia/<wiki>/a/ab/<file>
    final file = segments[4];
    final png = file.toLowerCase().endsWith('.svg') ? '.png' : '';
    path = [segments[0], segments[1], 'thumb', segments[2], segments[3], file, '${crestThumbnailWidth}px-$file$png'];
  } else {
    return url;
  }
  // Rebuilt from the decoded segments, so the query some links carry
  // (`?utm_source=…`) is dropped and every name is encoded exactly once.
  return Uri(scheme: 'https', host: uri.host, pathSegments: path).toString();
}

/// A score, home first.
class SportScore {
  final int home;
  final int away;

  const SportScore(this.home, this.away);

  @override
  bool operator ==(Object other) => other is SportScore && other.home == home && other.away == away;

  @override
  int get hashCode => Object.hash(home, away);

  @override
  String toString() => '$home:$away';
}

/// One goal, with the score it made.
class SportGoal {
  final int? minute;
  final String? scorer;
  final SportScore score;
  final bool isOwnGoal;
  final bool isPenalty;

  /// Scored in stoppage or extra time — what "90+3" is for.
  final bool isOvertime;

  const SportGoal({
    required this.minute,
    required this.scorer,
    required this.score,
    this.isOwnGoal = false,
    this.isPenalty = false,
    this.isOvertime = false,
  });

  static SportGoal? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final home = raw['scoreTeam1'];
    final away = raw['scoreTeam2'];
    if (home is! int || away is! int) return null;
    final minute = raw['matchMinute'];
    final scorer = raw['goalGetterName'];
    return SportGoal(
      minute: minute is int ? minute : null,
      scorer: scorer is String && scorer.trim().isNotEmpty ? scorer.trim() : null,
      score: SportScore(home, away),
      isOwnGoal: raw['isOwnGoal'] == true,
      isPenalty: raw['isPenalty'] == true,
      isOvertime: raw['isOvertime'] == true,
    );
  }

  /// Which side scored, read off the score it changed rather than off the
  /// scorer's club: an own goal counts for the other side, and the provider's
  /// team id on an own goal is not reliably either.
  bool scoredByHome(SportScore before) => score.home > before.home;
}

/// A matchday — "4. Spieltag" — by its position in the season.
class SportMatchday {
  final int order;
  final String name;

  const SportMatchday({required this.order, required this.name});

  static SportMatchday? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final order = raw['groupOrderID'];
    final name = raw['groupName'];
    if (order is! int) return null;
    return SportMatchday(order: order, name: name is String ? name : '$order');
  }
}

/// One fixture.
class SportMatch {
  final int id;
  final int season;
  final SportMatchday matchday;

  /// Local time. Built from the provider's UTC field: its "local" one is
  /// Germany's clock, which is only right for a television in Germany.
  final DateTime kickoff;
  final SportTeam home;
  final SportTeam away;
  final bool isFinished;

  /// The official result once there is one: after extra time where the
  /// game went into it (a cup tie), otherwise after ninety minutes.
  final SportScore? result;

  /// A cup tie that went into extra time ([result] is the score after it).
  final bool afterExtraTime;

  /// The shoot-out's score, for a cup tie decided by one.
  final SportScore? penalties;
  final SportScore? halftime;
  final List<SportGoal> goals;
  final String? stadium;
  final String? city;
  final int? spectators;

  const SportMatch({
    required this.id,
    required this.season,
    required this.matchday,
    required this.kickoff,
    required this.home,
    required this.away,
    required this.isFinished,
    this.result,
    this.afterExtraTime = false,
    this.penalties,
    this.halftime,
    this.goals = const [],
    this.stadium,
    this.city,
    this.spectators,
  });

  static SportMatch? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['matchID'];
    final season = raw['leagueSeason'];
    final matchday = SportMatchday.fromJson(raw['group']);
    final kickoff = _kickoff(raw);
    final home = SportTeam.fromJson(raw['team1']);
    final away = SportTeam.fromJson(raw['team2']);
    if (id is! int || season is! int || matchday == null || kickoff == null || home == null || away == null) {
      return null;
    }

    SportScore? result;
    SportScore? extraTime;
    SportScore? penalties;
    SportScore? halftime;
    final results = raw['matchResults'];
    if (results is List) {
      for (final entry in results) {
        if (entry is! Map) continue;
        final a = entry['pointsTeam1'];
        final b = entry['pointsTeam2'];
        if (a is! int || b is! int) continue;
        // Type 1 is the half-time score, type 2 the result after ninety
        // minutes; a cup tie adds type 3, the score after extra time (named
        // "Nachspielzeit"), and type 5, the shoot-out. A league match has
        // neither.
        switch (entry['resultTypeID']) {
          case 1:
            halftime = SportScore(a, b);
          case 2:
            result = SportScore(a, b);
          case 3:
            extraTime = SportScore(a, b);
          case 5:
            penalties = SportScore(a, b);
        }
      }
    }

    final goals = <SportGoal>[
      if (raw['goals'] case final List list)
        for (final entry in list)
          if (SportGoal.fromJson(entry) case final SportGoal goal) goal,
    ]..sort((a, b) => (a.score.home + a.score.away).compareTo(b.score.home + b.score.away));

    final location = raw['location'];
    String? text(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;
    final spectators = raw['numberOfViewers'];

    return SportMatch(
      id: id,
      season: season,
      matchday: matchday,
      kickoff: kickoff,
      home: home,
      away: away,
      isFinished: raw['matchIsFinished'] == true,
      result: extraTime ?? result,
      afterExtraTime: extraTime != null,
      penalties: penalties,
      halftime: halftime,
      goals: goals,
      stadium: location is Map ? text(location['locationStadium']) : null,
      city: location is Map ? text(location['locationCity']) : null,
      spectators: spectators is int && spectators > 0 ? spectators : null,
    );
  }

  static DateTime? _kickoff(Map raw) {
    final utc = raw['matchDateTimeUTC'];
    if (utc is String) {
      final parsed = DateTime.tryParse(utc);
      if (parsed != null) return parsed.toLocal();
    }
    final local = raw['matchDateTime'];
    return local is String ? DateTime.tryParse(local) : null;
  }

  /// Whether the whistle has gone and the final one has not.
  ///
  /// The provider's own flag says when it is over; when it began is only the
  /// kickoff time. A match more than three hours past kickoff that is still
  /// not marked finished is a provider that stopped updating, not a match
  /// still being played.
  bool isLive(DateTime now) =>
      !isFinished && !now.isBefore(kickoff) && now.isBefore(kickoff.add(const Duration(hours: 3)));

  /// The score to show: the official one once it exists, otherwise the one
  /// the goals so far add up to, and nothing before kickoff.
  SportScore? scoreAt(DateTime now) {
    if (result != null) return result;
    if (goals.isNotEmpty) return goals.last.score;
    if (isFinished || isLive(now)) return const SportScore(0, 0);
    return null;
  }
}

/// One line of the league table. Arrives in table order; [position] is that
/// order, counted from one.
class SportTableRow {
  final int position;
  final SportTeam team;
  final int played;
  final int won;
  final int drawn;
  final int lost;
  final int goalsFor;
  final int goalsAgainst;
  final int points;

  const SportTableRow({
    required this.position,
    required this.team,
    required this.played,
    required this.won,
    required this.drawn,
    required this.lost,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.points,
  });

  int get goalDifference => goalsFor - goalsAgainst;

  static List<SportTableRow> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    final rows = <SportTableRow>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final team = SportTeam.fromJson(entry);
      if (team == null) continue;
      int number(String key) => entry[key] is int ? entry[key] as int : 0;
      rows.add(
        SportTableRow(
          position: rows.length + 1,
          team: team,
          played: number('matches'),
          won: number('won'),
          drawn: number('draw'),
          lost: number('lost'),
          goalsFor: number('goals'),
          goalsAgainst: number('opponentGoals'),
          points: number('points'),
        ),
      );
    }
    return rows;
  }
}
