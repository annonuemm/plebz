import '../../models/livetv_channel.dart';
import '../../models/livetv_program.dart';
import '../../utils/live_tv_matching.dart';
import 'sport_models.dart';

/// What a found broadcast is to the fixture it was found for.
enum SportBroadcastKind {
  /// The guide names both clubs: this game, on this channel.
  match,

  /// A Konferenz of the league, running while the game is played.
  conference,

  /// Nothing named the game; a channel of the viewer's own group for the
  /// league, offered because it is where the game most likely is.
  leagueChannel,
}

/// One place to watch a fixture: a channel, and the guide entry that put it
/// there — null for a [SportBroadcastKind.leagueChannel] with no guide.
class SportBroadcast {
  final LiveTvChannel channel;
  final LiveTvProgram? program;
  final SportBroadcastKind kind;

  const SportBroadcast({required this.channel, required this.program, required this.kind});
}

/// When a game is looked for in the guide: a quarter of an hour after
/// kickoff. A programme on air then is the broadcast; one that ended at
/// kickoff was the build-up, one that starts later was the analysis.
const sportBroadcastProbe = Duration(minutes: 15);

/// [text] as the matching compares it: lower case, `ä`/`ae` and friends to one
/// vowel, `ß` to `ss`, every other character a space, runs of spaces as one.
///
/// Folding both spellings to the same letter is what lets "Köln", "Koeln" and
/// "Koln" meet, and "Mönchengladbach" the guide that writes it without the
/// umlaut. The same fold runs over the club names and the guide, so a word
/// mangled by it is mangled the same way on both sides.
String sportFold(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final folded = _foldedLetters[char];
    if (folded != null) {
      buffer.write(folded);
    } else if (_plain.hasMatch(char)) {
      buffer.write(char);
    } else {
      buffer.write(' ');
    }
  }
  final spelled = buffer.toString().replaceAll('ae', 'a').replaceAll('oe', 'o').replaceAll('ue', 'u');
  return spelled.split(' ').where((word) => word.isNotEmpty).join(' ');
}

final _plain = RegExp('[a-z0-9]');

const _foldedLetters = {
  'ä': 'a',
  'ö': 'o',
  'ü': 'u',
  'ß': 'ss',
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'í': 'i',
  'ó': 'o',
  'ò': 'o',
  'ø': 'o',
  'ú': 'u',
  'ç': 'c',
  'ñ': 'n',
  'š': 's',
  'č': 'c',
  'ć': 'c',
  'ž': 'z',
  'ı': 'i',
};

/// Words several clubs share, which on their own name none of them.
const _sharedWords = {
  'borussia',
  'eintracht',
  'fortuna',
  'viktoria',
  'sport',
  'sportverein',
  'verein',
  'club',
  'city',
  'spvgg',
  'rot',
  'weiss',
  'blau',
  'schwarz',
};

/// What guides call a club that none of its names contain.
const _aliasesByShortName = {
  'dortmund': ['bvb'],
  'hsv': ['hamburg'],
};

/// Everything a guide might call [team], folded: its full and short name as
/// they stand, each distinctive word of them, and the odd abbreviation
/// ("BVB"). "Borussia" names two clubs and so names neither.
Set<String> sportTeamTokens(SportTeam team) {
  final tokens = <String>{};
  for (final name in {team.name, team.shortName}) {
    final folded = sportFold(name);
    if (folded.length >= 3) tokens.add(folded);
    for (final word in folded.split(' ')) {
      if (word.length >= 4 && !_sharedWords.contains(word)) tokens.add(word);
    }
    tokens.addAll(_aliasesByShortName[folded] ?? const []);
  }
  return tokens;
}

bool _names(String folded, Set<String> tokens) {
  final padded = ' $folded ';
  return tokens.any((token) => padded.contains(' $token '));
}

bool _hasWords(String folded, List<String> phrases) {
  final padded = ' $folded ';
  return phrases.any((phrase) => padded.contains(' $phrase '));
}

/// The league [folded] names, if any: "3. Liga", "2. Bundesliga" (or
/// "2. Liga"), or plain "Bundesliga".
SportLeague? _leagueNamedIn(String folded) {
  if (_hasWords(folded, const ['3 liga', 'dritte liga', '3 fussball liga'])) return SportLeague.liga3;
  if (_hasWords(folded, const ['2 bundesliga', 'zweite bundesliga', '2 liga'])) return SportLeague.bundesliga2;
  if (_hasWords(folded, const ['bundesliga'])) return SportLeague.bundesliga1;
  return null;
}

/// Words that make a programme a football broadcast, for the one case that
/// needs telling: both clubs named only in the description. Football, not
/// sport and not "live": "Sky Sport News" and "Sportschau live" mention the
/// pairing without showing it. A genre tag or a Bundesliga channel counts.
const _footballHints = ['bundesliga', 'liga', 'fussball', 'football', 'soccer', 'konferenz'];

String _titleText(LiveTvProgram program) =>
    sportFold([program.title, ?program.subtitle, ?program.grandparentTitle, ?program.parentTitle].join(' '));

bool _coversProbe(LiveTvProgram program, int probe) {
  final begins = program.beginsAt;
  final ends = program.endsAt;
  return begins != null && ends != null && begins <= probe && ends > probe;
}

/// Where [match] of [league] can be watched, going by the guide.
///
/// A programme is the game when it is on air [sportBroadcastProbe] after
/// kickoff and names both clubs — in its titles, or, for a programme that
/// otherwise reads as football, in its description. A Konferenz of the same
/// league on air then comes after them; a "2. Bundesliga" Konferenz does not
/// count for the first.
///
/// One entry per programme: a station listed in several qualities shares
/// one guide, and the first copy in [channels] — the viewer's own order —
/// stands for the rest. The game before the Konferenz, then the programme
/// that starts closest to kickoff.
List<SportBroadcast> findSportBroadcasts({
  required SportMatch match,
  required SportLeague league,
  required List<LiveTvChannel> channels,
  required Iterable<LiveTvProgram> programs,
}) {
  final kickoff = match.kickoff.millisecondsSinceEpoch ~/ 1000;
  final probe = kickoff + sportBroadcastProbe.inSeconds;
  final home = sportTeamTokens(match.home);
  final away = sportTeamTokens(match.away);
  final byIdentifier = _channelsByIdentifier(channels);

  final found = <({SportBroadcast broadcast, int rank})>[];
  for (final program in programs) {
    if (!_coversProbe(program, probe)) continue;
    final titles = _titleText(program);
    int? rank;
    SportBroadcastKind? kind;
    if (_names(titles, home) && _names(titles, away)) {
      kind = SportBroadcastKind.match;
      rank = 0;
    } else if (_hasWords(titles, const ['konferenz'])) {
      kind = SportBroadcastKind.conference;
      rank = 2;
    } else {
      final summary = sportFold(program.summary ?? '');
      if (_names(summary, home) && _names(summary, away)) {
        kind = SportBroadcastKind.match;
        rank = 1;
      }
    }
    if (kind == null || rank == null) continue;

    for (final channel in _channelsOf(program, byIdentifier)) {
      if (kind == SportBroadcastKind.conference) {
        // The programme's own words decide the league; only a Konferenz that
        // names none borrows the channel's ("Sky Sport Bundesliga 1").
        final named =
            _leagueNamedIn(sportFold('$titles ${program.summary ?? ''}')) ??
            _leagueNamedIn(sportFold(channel.displayName));
        if (named != league) continue;
      }
      if (rank == 1) {
        final hints = sportFold([titles, ...?program.genres, channel.displayName, channel.lineup ?? ''].join(' '));
        if (!_hasWords(hints, _footballHints)) continue;
      }
      found.add((broadcast: SportBroadcast(channel: channel, program: program, kind: kind), rank: rank));
    }
  }

  final order = {for (var i = 0; i < channels.length; i++) liveTvChannelScopeKey(channels[i]): i};
  found.sort((a, b) {
    final byRank = a.rank.compareTo(b.rank);
    if (byRank != 0) return byRank;
    final aOff = ((a.broadcast.program!.beginsAt ?? 0) - kickoff).abs();
    final bOff = ((b.broadcast.program!.beginsAt ?? 0) - kickoff).abs();
    if (aOff != bOff) return aOff.compareTo(bOff);
    return (order[liveTvChannelScopeKey(a.broadcast.channel)] ?? 0).compareTo(
      order[liveTvChannelScopeKey(b.broadcast.channel)] ?? 0,
    );
  });

  final seen = <String>{};
  return [
    for (final entry in found)
      if (seen.add(_airingKey(entry.broadcast))) entry.broadcast,
  ];
}

/// Words in a channel's name that make it another sport's, or another
/// country's, whoever runs it: "MagentaSport Eishockey", "Sky Sport Austria".
/// Folded like the names they are looked for in — the fold makes "frauen"
/// "fraun" and "league" "leagu".
final _otherSports = [for (final word in _otherSportWords) sportFold(word)];

const _otherSportWords = [
  'frauen',
  'basketball',
  'eishockey',
  'hockey',
  'handball',
  'tennis',
  'golf',
  'darts',
  'nfl',
  'nba',
  'nhl',
  'f1',
  'formel',
  'motorsport',
  'boxen',
  'ufc',
  'premier league',
  'laliga',
  'serie a',
  'ligue 1',
  'austria',
];

final _dazn = RegExp(r'(^| )dazn[0-9]*( |$)');

/// The leagues a channel carries by who broadcasts it, read off its name
/// whatever a playlist puts around it ("DE: DAZN 1 FHD"). The rights of
/// 2025/26 to 2028/29 and, for the 3. Liga, to 2026/27:
///
/// * Sky — the Bundesliga's single games and the whole 2. Bundesliga, on its
///   Bundesliga channels, Top Event and Mix. Sky Sport News shows no game,
///   and "Sky Sports" is the British one.
/// * DAZN — the Bundesliga's Saturday Konferenz and its Sundays.
/// * MagentaSport — every game of the 3. Liga.
///
/// A league, not a kickoff: the list offers every channel that may carry the
/// game, not a guess at the one that will.
Set<SportLeague> sportBroadcasterLeagues(String channelName) {
  final folded = sportFold(channelName);
  if (_hasWords(folded, _otherSports)) return const {};
  final compact = folded.replaceAll(' ', '');
  if (compact.contains('magentasport')) return const {SportLeague.liga3};
  if (_dazn.hasMatch(folded)) return const {SportLeague.bundesliga1};
  final sky = _hasWords(folded, const ['sky']) || compact.contains('skysport') || compact.contains('skybundesliga');
  if (sky &&
      !_hasWords(folded, const ['sports', 'news']) &&
      (_hasWords(folded, const ['bundesliga', 'top event', 'mix']) || compact.contains('topevent'))) {
    return const {SportLeague.bundesliga1, SportLeague.bundesliga2};
  }
  return const {};
}

/// The viewer's own channels for [league], for when the guide names nothing:
/// the channels of a group that names the league ("Sport • Bundesliga"),
/// then channels whose own name does ("Sky Sport Bundesliga 3"), then the
/// channels of the league's broadcasters ("DAZN 1", "MagentaSport 2"), see
/// [sportBroadcasterLeagues]. A Bundesliga group serves both Bundesligen —
/// the same channels carry them — but not the 3. Liga. Each comes with what
/// is on it at the game, when the guide knows.
List<SportBroadcast> sportLeagueChannels({
  required SportMatch match,
  required SportLeague league,
  required List<LiveTvChannel> channels,
  required Iterable<LiveTvProgram> programs,
  int limit = 12,
}) {
  bool carries(String name) {
    final named = _leagueNamedIn(sportFold(name));
    if (named == null) return false;
    if (league == SportLeague.liga3) return named == SportLeague.liga3;
    return named != SportLeague.liga3;
  }

  final byGroup = channels.where((channel) => carries(channel.lineup ?? '')).toList();
  final byName = channels.where((channel) => !carries(channel.lineup ?? '') && carries(channel.displayName)).toList();
  final taken = {...byGroup, ...byName};
  final picked = <LiveTvChannel>[
    ...byGroup,
    ...byName,
    ...channels.where(
      (channel) => !taken.contains(channel) && sportBroadcasterLeagues(channel.displayName).contains(league),
    ),
  ];
  if (picked.isEmpty) return const [];

  final probe = match.kickoff.millisecondsSinceEpoch ~/ 1000 + sportBroadcastProbe.inSeconds;
  final byIdentifier = _channelsByIdentifier(picked);
  final onAir = <String, LiveTvProgram>{};
  for (final program in programs) {
    if (!_coversProbe(program, probe)) continue;
    for (final channel in _channelsOf(program, byIdentifier)) {
      onAir.putIfAbsent(liveTvChannelScopeKey(channel), () => program);
    }
  }

  final seen = <String>{};
  final result = <SportBroadcast>[];
  for (final channel in picked) {
    final program = onAir[liveTvChannelScopeKey(channel)];
    final broadcast = SportBroadcast(channel: channel, program: program, kind: SportBroadcastKind.leagueChannel);
    if (!seen.add(program == null ? liveTvChannelScopeKey(channel) : _airingKey(broadcast))) continue;
    result.add(broadcast);
    if (result.length == limit) break;
  }
  return result;
}

/// One airing: a programme on a station, however many copies list it.
String _airingKey(SportBroadcast broadcast) =>
    '${broadcast.channel.identifier ?? liveTvChannelScopeKey(broadcast.channel)}@${broadcast.program?.beginsAt}';

Map<String, List<LiveTvChannel>> _channelsByIdentifier(List<LiveTvChannel> channels) {
  final index = <String, List<LiveTvChannel>>{};
  for (final channel in channels) {
    for (final id in {channel.key, ?liveTvNonEmpty(channel.identifier)}) {
      (index[id] ??= []).add(channel);
    }
  }
  return index;
}

Iterable<LiveTvChannel> _channelsOf(LiveTvProgram program, Map<String, List<LiveTvChannel>> byIdentifier) {
  final id = liveTvNonEmpty(program.channelIdentifier);
  if (id == null) return const [];
  return (byIdentifier[id] ?? const []).where((channel) => liveTvProgramMatchesChannel(program, channel));
}
