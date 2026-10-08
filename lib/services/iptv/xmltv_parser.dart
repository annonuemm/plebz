import 'package:xml/xml_events.dart';

import '../../models/livetv_program.dart';

/// One `<programme>` of an XMLTV guide, still keyed by its XMLTV channel id.
class XmltvProgram {
  const XmltvProgram({
    required this.channelId,
    required this.title,
    required this.beginsAt,
    required this.endsAt,
    this.subtitle,
    this.summary,
    this.genres,
    this.country,
    this.year,
    this.episodeNumber,
    this.seasonNumber,
    this.icon,
  });

  /// The `channel` attribute — matches a channel's `tvg-id`.
  final String channelId;
  final String title;

  /// Epoch seconds.
  final int beginsAt;
  final int endsAt;

  /// `<sub-title>` — the episode's title, or for a sports broadcast often the
  /// pairing itself under a title that only names the competition.
  final String? subtitle;

  final String? summary;

  /// `<category>` tags, in document order.
  final List<String>? genres;

  /// `<country>`.
  final String? country;

  /// `<date>`, reduced to its year — guides write it as `2019` or `20190411`.
  final int? year;
  final int? episodeNumber;
  final int? seasonNumber;
  final String? icon;
}

/// XMLTV timestamps are `YYYYMMDDHHMMSS` with an optional ` +ZZZZ` offset.
///
/// The offset is genuinely optional in the wild; without one the time is the
/// guide's local time, which is the best assumption available.
final _timePattern = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4})?$');

/// `S.E.P` with zero-based, possibly open, parts — "0.4." is season 1
/// episode 5.
final _xmltvNsPattern = RegExp(r'^\s*(\d+)?\s*\.\s*(\d+)?\s*\.');

int? parseXmltvTime(String? value) {
  if (value == null) return null;
  final match = _timePattern.firstMatch(value.trim());
  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.tryParse(match.group(6) ?? '0') ?? 0;
  final offset = match.group(7);

  if (offset == null) {
    final local = DateTime(year, month, day, hour, minute, second);
    return local.millisecondsSinceEpoch ~/ 1000;
  }

  final sign = offset.startsWith('-') ? -1 : 1;
  final offsetMinutes = sign * (int.parse(offset.substring(1, 3)) * 60 + int.parse(offset.substring(3, 5)));
  final asUtc = DateTime.utc(year, month, day, hour, minute, second);
  return asUtc.subtract(Duration(minutes: offsetMinutes)).millisecondsSinceEpoch ~/ 1000;
}

/// What one guide yielded: its programmes, plus the channel ids it declared
/// under a name the caller was looking for.
class XmltvGuide {
  const XmltvGuide({required this.programs, this.matchedChannelNames = const {}, this.channelIcons = const {}});

  final List<XmltvProgram> programs;

  /// XMLTV channel id → the normalized display name that matched. Only ids
  /// the caller did not already know by `tvg-id` appear here.
  final Map<String, String> matchedChannelNames;

  /// XMLTV channel id → the logo its `<channel>` block names in `<icon>`, for
  /// the ids the caller asked for or that matched by name. What a channel
  /// whose playlist entry carries no logo can be shown with instead.
  final Map<String, String> channelIcons;
}

final _nameSeparatorPattern = RegExp(r'[^a-z0-9]+');

/// The words of a channel name, lowercased and stripped of punctuation.
List<String> _channelNameWords(String value) =>
    value.toLowerCase().split(_nameSeparatorPattern).where((word) => word.isNotEmpty).toList();

/// Trailing words that say how a channel is encoded rather than which
/// channel it is.
const _qualitySuffixes = <String>{'fullhd', 'hevc', 'h265', 'fhd', 'uhd', 'shd', 'hd', 'sd', '4k', 'raw'};

/// A word made of nothing but those markers, written together: "HDraw",
/// "FHDraw", "HDHEVC". Guides name whole line-ups that way ("Sky Bundesliga
/// 2 HDraw"), and a playlist calling the same channel "Sky Bundesliga 2 HD"
/// never met them.
final _gluedQuality = RegExp('^(?:${_qualitySuffixes.join('|')})+\$');

/// The keys [value] may be known by: its full name, and every form with a
/// trailing quality word removed. One side writing "ZDF HD" where the other
/// writes "ZDF" is the single most common reason a guide and a playlist
/// disagree about a name, and either side may be the one carrying the marker
/// — so both register every variant and meet in the middle.
///
/// Stripping works on whole words, never on letters: "ZDF HD" compacts to
/// `zdfhd`, which *ends* with `fhd` without containing that marker at all.
Set<String> xmltvChannelNameVariants(String value) {
  final words = _channelNameWords(value);
  final variants = <String>{};
  while (words.isNotEmpty) {
    variants.add(words.join());
    if (!_gluedQuality.hasMatch(words.last) || words.length == 1) break;
    words.removeLast();
  }
  return variants;
}

/// Parse an XMLTV guide into programmes.
///
/// Event-driven rather than DOM-based on purpose: providers routinely ship
/// guides of tens of megabytes covering a fortnight, and building a document
/// tree for one would hold the whole thing in memory at once.
///
/// [channelIds], when given, restricts the result to those XMLTV ids — the
/// usual case, where a playlist carries a few hundred channels and the guide
/// covers thousands. [channelNames] widens that: an id whose `<channel>`
/// block declares one of these normalized display names is kept as well,
/// which is what rescues a playlist whose `tvg-id`s do not line up with its
/// guide. It relies on the `<channel>` blocks preceding the programmes, as
/// every guide in the wild writes them.
XmltvGuide parseXmltvGuide(String contents, {Set<String>? channelIds, Set<String> channelNames = const {}}) {
  final reader = XmltvGuideReader(channelIds: channelIds, channelNames: channelNames);
  for (final event in parseEvents(contents)) {
    reader.add(event);
  }
  return reader.finish();
}

/// [parseXmltvGuide] one event at a time (Plebz), so a guide can be read as it
/// arrives — chunk by chunk off the network — rather than once it is whole in
/// memory. Feed it every event of the document in order, then [finish].
class XmltvGuideReader {
  XmltvGuideReader({this.channelIds, this.channelNames = const {}});

  final Set<String>? channelIds;
  final Set<String> channelNames;

  final _programs = <XmltvProgram>[];
  final _matchedChannelNames = <String, String>{};

  String? _channelId;
  int? _begins;
  int? _ends;
  String? _title;
  String? _subtitle;
  String? _summary;
  List<String>? _genres;
  String? _country;
  int? _year;
  String? _icon;
  int? _episode;
  int? _season;
  String? _currentText;
  String? _episodeSystem;
  var _inProgramme = false;
  var _keep = false;
  String? _channelBlockId;
  // Every declaration block, not only those read for their names: the icon
  // is wanted for channels known by id as well.
  String? _declaredChannelId;
  final _channelIcons = <String, String>{};

  void _reset() {
    _channelId = null;
    _begins = null;
    _ends = null;
    _title = null;
    _subtitle = null;
    _summary = null;
    _genres = null;
    _country = null;
    _year = null;
    _icon = null;
    _episode = null;
    _season = null;
    _currentText = null;
    _episodeSystem = null;
  }

  void add(XmlEvent event) {
    final channelIds = this.channelIds;
    if (event is XmlStartElementEvent) {
      switch (event.name) {
        case 'channel':
          // The declaration block, not a programme: read to learn the names
          // this id answers to, and the logo it is drawn with.
          if (!event.isSelfClosing) _declaredChannelId = _attribute(event, 'id');
          if (channelNames.isNotEmpty && !event.isSelfClosing) _channelBlockId = _attribute(event, 'id');
        case 'programme':
          _inProgramme = true;
          _reset();
          final channelId = _channelId = _attribute(event, 'channel');
          _begins = parseXmltvTime(_attribute(event, 'start'));
          _ends = parseXmltvTime(_attribute(event, 'stop'));
          _keep =
              channelId != null &&
              (channelIds == null || channelIds.contains(channelId) || _matchedChannelNames.containsKey(channelId));
        case 'icon':
          if (_inProgramme) {
            if (_keep) _icon ??= _attribute(event, 'src');
          } else if (_declaredChannelId case final id?) {
            final src = _attribute(event, 'src')?.trim();
            if (src != null && src.isNotEmpty) _channelIcons.putIfAbsent(id, () => src);
          }
        case 'episode-num':
          if (_inProgramme && _keep) _episodeSystem = _attribute(event, 'system');
      }
      // A self-closing element emits no end event, so its text can never
      // arrive; clearing here keeps a previous sibling's text from leaking.
      _currentText = null;
      return;
    }

    if (event is XmlTextEvent) {
      if ((_inProgramme && _keep) || _channelBlockId != null) _currentText = (_currentText ?? '') + event.value;
      return;
    }
    if (event is XmlCDATAEvent) {
      if ((_inProgramme && _keep) || _channelBlockId != null) _currentText = (_currentText ?? '') + event.value;
      return;
    }

    if (event is XmlEndElementEvent) {
      final text = _currentText?.trim();
      final keep = _keep;
      _currentText = null;
      switch (event.name) {
        case 'display-name':
          final id = _channelBlockId;
          if (id != null && !(channelIds?.contains(id) ?? false) && (text?.isNotEmpty ?? false)) {
            for (final variant in xmltvChannelNameVariants(text!)) {
              if (!channelNames.contains(variant)) continue;
              _matchedChannelNames.putIfAbsent(id, () => variant);
              break;
            }
          }
        case 'channel':
          _channelBlockId = null;
          _declaredChannelId = null;
        case 'title':
          if (keep && (text?.isNotEmpty ?? false)) _title ??= text;
        case 'sub-title':
          if (keep && (text?.isNotEmpty ?? false)) _subtitle ??= text;
        case 'desc':
          if (keep && (text?.isNotEmpty ?? false)) _summary ??= text;
        case 'category':
          // Several tags per programme, so collected rather than kept once.
          if (keep && (text?.isNotEmpty ?? false)) (_genres ??= <String>[]).add(text!);
        case 'country':
          if (keep && (text?.isNotEmpty ?? false)) _country ??= text;
        case 'date':
          // "2019" or "20190411": the year is the first four digits either way.
          if (keep && (text?.isNotEmpty ?? false)) {
            final digits = text!.trim();
            if (digits.length >= 4) _year ??= int.tryParse(digits.substring(0, 4));
          }
        case 'episode-num':
          if (keep && (text?.isNotEmpty ?? false)) {
            final parsed = _episodeNumbers(text!, system: _episodeSystem);
            _season ??= parsed.season;
            _episode ??= parsed.episode;
          }
        case 'programme':
          final begins = _begins;
          final ends = _ends;
          final title = _title;
          if (keep && begins != null && ends != null && title != null && title.isNotEmpty) {
            _programs.add(
              XmltvProgram(
                channelId: _channelId!,
                title: title,
                beginsAt: begins,
                endsAt: ends,
                subtitle: _subtitle,
                summary: _summary,
                genres: _genres,
                country: _country,
                year: _year,
                episodeNumber: _episode,
                seasonNumber: _season,
                icon: _icon,
              ),
            );
          }
          _inProgramme = false;
          _keep = false;
          _reset();
      }
    }
  }

  /// The guide read so far.
  XmltvGuide finish() {
    final channelIds = this.channelIds;
    // Only the channels this guide is read for: a guide declares thousands.
    _channelIcons.removeWhere((id, _) => !(channelIds?.contains(id) ?? true) && !_matchedChannelNames.containsKey(id));
    return XmltvGuide(programs: _programs, matchedChannelNames: _matchedChannelNames, channelIcons: _channelIcons);
  }
}

/// The programmes of [contents] — [parseXmltvGuide] without the name matching.
List<XmltvProgram> parseXmltv(String contents, {Set<String>? channelIds}) =>
    parseXmltvGuide(contents, channelIds: channelIds).programs;

/// [parseXmltvGuide] behind a single argument, so a guide can be parsed off
/// the UI isolate with `compute`. Providers ship guides of tens of megabytes,
/// and parsing one inline freezes the frame that asked for it.
XmltvGuide parseXmltvPayload(({String contents, Set<String> channelIds, Set<String> channelNames}) payload) =>
    parseXmltvGuide(payload.contents, channelIds: payload.channelIds, channelNames: payload.channelNames);

String? _attribute(XmlStartElementEvent event, String name) {
  for (final attribute in event.attributes) {
    if (attribute.name == name) {
      final value = attribute.value.trim();
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

({int? season, int? episode}) _episodeNumbers(String value, {String? system}) {
  // `onscreen` is free text ("S02E05"); `xmltv_ns` is the structured form and
  // is zero-based, which is the trap in this format.
  if (system == 'xmltv_ns') {
    final match = _xmltvNsPattern.firstMatch(value);
    if (match == null) return (season: null, episode: null);
    final season = match.group(1);
    final episode = match.group(2);
    return (
      season: season == null ? null : int.parse(season) + 1,
      episode: episode == null ? null : int.parse(episode) + 1,
    );
  }

  final onscreen = RegExp(r'S(\d+)\s*E(\d+)', caseSensitive: false).firstMatch(value);
  if (onscreen == null) return (season: null, episode: null);
  return (season: int.parse(onscreen.group(1)!), episode: int.parse(onscreen.group(2)!));
}

/// Map parsed guide entries onto the app's programme model, resolving XMLTV
/// channel ids against the channels a source actually carries.
List<LiveTvProgram> programsFromXmltv(
  List<XmltvProgram> parsed, {
  required Map<String, LiveTvChannelRef> channelsByXmltvId,
}) {
  final programs = <LiveTvProgram>[];

  for (final entry in parsed) {
    final channel = channelsByXmltvId[entry.channelId];
    if (channel == null) continue;
    programs.add(
      LiveTvProgram(
        key: 'iptv:${channel.key}:${entry.beginsAt}',
        title: entry.title,
        subtitle: entry.subtitle,
        summary: entry.summary,
        genres: entry.genres,
        country: entry.country,
        year: entry.year,
        beginsAt: entry.beginsAt,
        endsAt: entry.endsAt,
        index: entry.episodeNumber,
        parentIndex: entry.seasonNumber,
        thumb: entry.icon,
        // What the guide keys programmes on must identify the app's channel,
        // not the guide's id for it — a name match resolves an id the
        // channel never carried.
        channelIdentifier: channel.identifier ?? channel.key,
        channelCallSign: channel.callSign,
        serverId: channel.serverId,
        serverName: channel.serverName,
      ),
    );
  }

  programs.sort((a, b) => (a.beginsAt ?? 0).compareTo(b.beginsAt ?? 0));
  return programs;
}

/// The channel fields a guide entry needs to be attached to a channel, without
/// dragging the whole model into the parser.
class LiveTvChannelRef {
  const LiveTvChannelRef({required this.key, this.identifier, this.callSign, this.serverId, this.serverName});

  final String key;

  /// The channel's own EPG id (`tvg-id`). Absent for a channel that was
  /// matched by name instead.
  final String? identifier;

  final String? callSign;
  final String? serverId;
  final String? serverName;
}
