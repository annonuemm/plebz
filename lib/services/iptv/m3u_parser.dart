import '../../models/livetv_channel.dart';

import 'iptv_catchup.dart';

/// One entry of an extended M3U playlist, already split into the parts the
/// Live TV surfaces need.
class M3uEntry {
  const M3uEntry({
    required this.url,
    required this.name,
    this.tvgId,
    this.tvgName,
    this.logo,
    this.group,
    this.number,
    this.headers = const {},
    this.catchup = const IptvCatchupInfo(),
  });

  /// Stream URL. Never empty — the parser drops entries without one.
  final String url;

  /// Display name, taken from the text after the `#EXTINF` comma.
  final String name;

  /// EPG channel id (`tvg-id`). This is what an XMLTV guide keys on, so an
  /// entry without one can be watched but never gets a programme.
  final String? tvgId;
  final String? tvgName;
  final String? logo;
  final String? group;

  /// Channel number (`tvg-chno`), when the provider numbers its channels.
  final String? number;

  /// HTTP headers the stream needs, from `#EXTVLCOPT` directives or a
  /// pipe-suffixed URL. Providers that check the user agent hand out a
  /// playlist that plays nowhere without them.
  final Map<String, String> headers;

  /// What the entry says about its archive. Empty for the many playlists that
  /// carry none.
  final IptvCatchupInfo catchup;
}

final _attributePattern = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');

/// A day count, or null for the absent and the nonsensical. `catchup-time`
/// is seconds in some generators, so anything implausible as days is read as
/// seconds before it is given up on.
int? _positiveInt(String? raw) {
  final value = int.tryParse(raw?.trim() ?? '');
  if (value == null || value <= 0) return null;
  if (value <= 365) return value;
  final asDays = value ~/ 86400;
  return asDays > 0 ? asDays : null;
}

/// Parse an extended M3U playlist.
///
/// Written against what providers actually send rather than the loose spec:
/// attribute order varies, casing varies (`tvg-ID`, `tvg-id`), the duration
/// field may be `-1` or a real number, and the URL sits on one of the lines
/// after `#EXTINF` — providers routinely put `#EXTVLCOPT` or `#EXTGRP`
/// directives in between. Anything unparseable is skipped rather than
/// failing the whole playlist: one malformed entry in a 20,000-line file must
/// not cost the user every channel.
List<M3uEntry> parseM3u(String contents) {
  final entries = <M3uEntry>[];
  String? pendingInfo;
  String? pendingGroup;
  var pendingHeaders = <String, String>{};

  for (final rawLine in contents.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#EXTINF')) {
      pendingInfo = line;
      pendingGroup = null;
      pendingHeaders = {};
      continue;
    }
    // `#EXTGRP:` is the older way of stating a group; it applies to the entry
    // that follows and loses to an explicit `group-title` attribute.
    if (line.startsWith('#EXTGRP:')) {
      pendingGroup = line.substring('#EXTGRP:'.length).trim();
      continue;
    }
    if (line.startsWith('#EXTVLCOPT:')) {
      _readVlcOption(line.substring('#EXTVLCOPT:'.length), into: pendingHeaders);
      continue;
    }
    // Any other directive (#EXTM3U, comments) is not a URL.
    if (line.startsWith('#')) continue;

    final info = pendingInfo;
    pendingInfo = null;
    final group = pendingGroup;
    pendingGroup = null;
    final headers = pendingHeaders;
    pendingHeaders = {};
    if (info == null) continue;

    final entry = _entryFrom(info, line, fallbackGroup: group, headers: headers);
    if (entry != null) entries.add(entry);
  }

  return entries;
}

/// VLC's playlist options. Only the two that decide whether a stream plays
/// are read; the rest (`network-caching`, deinterlace hints) are player
/// settings this app does not take from a playlist.
void _readVlcOption(String option, {required Map<String, String> into}) {
  final separator = option.indexOf('=');
  if (separator <= 0) return;
  final name = option.substring(0, separator).trim().toLowerCase();
  final value = option.substring(separator + 1).trim();
  if (value.isEmpty) return;
  switch (name) {
    case 'http-user-agent':
      into['User-Agent'] = value;
    case 'http-referrer':
      into['Referer'] = value;
  }
}

/// Kodi-style headers appended to the URL (`…/stream.ts|User-Agent=VLC`).
/// The pipe is not a legal URL character, so everything after the first one
/// is header material.
(String, Map<String, String>) _splitUrlHeaders(String url) {
  final pipe = url.indexOf('|');
  if (pipe < 0) return (url, const {});

  final headers = <String, String>{};
  for (final pair in url.substring(pipe + 1).split('&')) {
    final separator = pair.indexOf('=');
    if (separator <= 0) continue;
    final name = pair.substring(0, separator).trim();
    final value = Uri.decodeComponent(pair.substring(separator + 1).trim());
    if (name.isEmpty || value.isEmpty) continue;
    headers[name] = value;
  }
  return (url.substring(0, pipe), headers);
}

M3uEntry? _entryFrom(String info, String rawUrl, {String? fallbackGroup, Map<String, String> headers = const {}}) {
  if (rawUrl.isEmpty) return null;
  final (url, urlHeaders) = _splitUrlHeaders(rawUrl);
  if (url.isEmpty) return null;

  final attributes = <String, String>{};
  for (final match in _attributePattern.allMatches(info)) {
    attributes[match.group(1)!.toLowerCase()] = match.group(2)!;
  }

  // The display name is everything after the last comma that is not inside an
  // attribute value — providers put commas in titles ("Sports, HD"), so the
  // split point is the comma following the final closing quote.
  final lastQuote = info.lastIndexOf('"');
  final commaIndex = info.indexOf(',', lastQuote == -1 ? 0 : lastQuote);
  final name = commaIndex == -1 ? '' : info.substring(commaIndex + 1).trim();

  final tvgName = attributes['tvg-name']?.trim();
  final displayName = name.isNotEmpty ? name : (tvgName?.isNotEmpty ?? false ? tvgName! : url);

  String? nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  return M3uEntry(
    url: url,
    name: displayName,
    tvgId: nonEmpty(attributes['tvg-id']),
    tvgName: nonEmpty(tvgName),
    logo: nonEmpty(attributes['tvg-logo']),
    group: nonEmpty(attributes['group-title']) ?? nonEmpty(fallbackGroup),
    number: nonEmpty(attributes['tvg-chno']),
    // Archive attributes. Spellings differ by generator, which is why each
    // one is looked up under every name it is written as in the wild.
    catchup: IptvCatchupInfo(
      declaredMode: nonEmpty(
        attributes['catchup'] ?? attributes['catchup-type'] ?? attributes['tvg-rec-type'],
      )?.toLowerCase(),
      source: nonEmpty(attributes['catchup-source'] ?? attributes['catchup-template']),
      days: _positiveInt(
        attributes['catchup-days'] ?? attributes['catchup-time'] ?? attributes['tvg-rec'] ?? attributes['timeshift'],
      ),
    ),
    // A header on the URL is the more specific statement, so it wins over
    // the entry's `#EXTVLCOPT`.
    headers: {...headers, ...urlHeaders},
  );
}

/// Map playlist entries onto the app's channel model.
///
/// [sourceId] namespaces the channel key so two playlists holding the same
/// stream stay distinguishable, and [sourceName] is what the UI shows as the
/// channel's origin.
List<LiveTvChannel> channelsFromM3u(
  List<M3uEntry> entries, {
  required String sourceId,
  required String sourceName,
  IptvCatchupMode catchupMode = IptvCatchupMode.automatic,
  int? sourceCatchupDays,
}) {
  final channels = <LiveTvChannel>[];
  final seenKeys = <String>{};

  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    // The URL identifies the stream, but duplicates happen; the index keeps
    // the key unique without making it depend on list order alone.
    var key = 'iptv:$sourceId:${entry.tvgId ?? entry.url}';
    if (!seenKeys.add(key)) {
      key = '$key#$index';
      seenKeys.add(key);
    }
    channels.add(
      LiveTvChannel(
        key: key,
        identifier: entry.tvgId,
        title: entry.name,
        thumb: entry.logo,
        number: entry.number ?? '${index + 1}',
        lineup: entry.group,
        serverId: sourceId,
        serverName: sourceName,
        liveTvSourceTitle: sourceName,
        // Must match `IptvLiveTvSource.buildFavoriteChannelSource`: the Live
        // TV screen keys the favorites store by the source URI, and a bare
        // id would never find its store.
        favoriteSource: 'iptv://$sourceId',
        favoriteStoreKey: 'iptv:$sourceId',
        catchupDays: iptvCatchupWindowDays(mode: catchupMode, info: entry.catchup, sourceDays: sourceCatchupDays),
      ),
    );
  }

  return channels;
}
