import 'dart:convert';

import '../../models/livetv_channel.dart';
import '../../models/livetv_program.dart';

import 'iptv_catchup.dart';
import 'iptv_source.dart';

/// Xtream Codes request builder.
///
/// The panel exposes one JSON endpoint (`player_api.php`) that takes the
/// credentials as query parameters, and serves streams from a path built from
/// the same credentials. Both are assembled here so the shapes stay in one
/// place and can be checked without a server.
class XtreamApi {
  const XtreamApi({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.streamFormat = IptvStreamFormat.mpegTs,
  });

  final String baseUrl;
  final String username;
  final String password;

  /// The container live channels are requested in.
  final IptvStreamFormat streamFormat;

  /// The panel root without a trailing slash, so path joins stay predictable.
  String get _root {
    var root = baseUrl.trim();
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    return root;
  }

  Uri _api(Map<String, String> parameters) => Uri.parse(
    '$_root/player_api.php',
  ).replace(queryParameters: {'username': username, 'password': password, ...parameters});

  /// Account probe. Also the cheapest way to verify credentials.
  Uri userInfo() => _api(const {});

  Uri liveCategories() => _api(const {'action': 'get_live_categories'});

  Uri liveStreams({String? categoryId}) => _api({
    'action': 'get_live_streams',
    ...?(categoryId == null ? null : {'category_id': categoryId}),
  });

  /// The next [limit] programmes on one channel. Xtream has no full-guide
  /// endpoint; the guide is assembled per channel from this.
  Uri shortEpg(String streamId, {int limit = 12}) =>
      _api({'action': 'get_short_epg', 'stream_id': streamId, 'limit': '$limit'});

  /// The panel's whole guide as XMLTV. Not part of `player_api.php`: it is
  /// its own endpoint, and the only one that returns more than one channel's
  /// programmes at a time.
  Uri xmltv() => Uri.parse('$_root/xmltv.php').replace(queryParameters: {'username': username, 'password': password});

  /// Live stream URL, in whichever container the source asked for.
  ///
  /// Not every panel serves both well: one that answers the HLS path with a
  /// redirect loop or an error plays fine over the transport stream, and the
  /// other way round behind some proxies. Which is why this is a choice and
  /// not a constant.
  Uri liveStreamUrl(String streamId) =>
      Uri.parse('$_root/live/$username/$password/$streamId.${streamFormat.extension}');

  /// The panel root, for the archive path built in
  /// [buildIptvCatchupUrl] — it needs the same three pieces this class holds.
  String get root => _root;
}

/// Map `get_live_streams` rows onto channels.
///
/// Field names are taken as the panels send them: `stream_id` is numeric in
/// some builds and a string in others, `epg_channel_id` is the XMLTV id and is
/// frequently absent, and `num` is the channel number.
List<LiveTvChannel> channelsFromXtream(
  List<dynamic> rows, {
  required String sourceId,
  required String sourceName,
  Map<String, String> categoryNames = const {},
  IptvCatchupMode catchupMode = IptvCatchupMode.automatic,
  int? sourceCatchupDays,
}) {
  final channels = <LiveTvChannel>[];

  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    if (row is! Map) continue;
    final streamId = _string(row['stream_id']);
    if (streamId == null) continue;

    final categoryId = _string(row['category_id']);
    channels.add(
      LiveTvChannel(
        key: 'iptv:$sourceId:$streamId',
        identifier: _string(row['epg_channel_id']),
        title: _string(row['name']) ?? 'Kanal $streamId',
        thumb: _string(row['stream_icon']),
        number: _string(row['num']) ?? '${index + 1}',
        lineup: categoryId == null ? null : categoryNames[categoryId],
        serverId: sourceId,
        serverName: sourceName,
        liveTvSourceTitle: sourceName,
        // Must match `IptvLiveTvSource.buildFavoriteChannelSource`: the Live
        // TV screen keys the favorites store by the source URI, and a bare
        // id would never find its store.
        favoriteSource: 'iptv://$sourceId',
        favoriteStoreKey: 'iptv:$sourceId',
        // `tv_archive` is the flag, `tv_archive_duration` the window in days.
        // Panels send both as numbers in some builds and as strings in
        // others, and a few set the duration without ever raising the flag.
        catchupDays: iptvCatchupWindowDays(
          mode: catchupMode,
          providerDays: _archiveDays(row),
          sourceDays: sourceCatchupDays,
        ),
      ),
    );
  }

  return channels;
}

/// The channel's archive window in days, or null when it has none.
int? _archiveDays(Map<dynamic, dynamic> row) {
  final days = int.tryParse(_string(row['tv_archive_duration']) ?? '');
  final flag = _string(row['tv_archive']);
  final enabled = flag == '1' || flag == 'true';
  if (days != null && days > 0) return days;
  // The flag alone says there is an archive but not how deep. A day is the
  // honest floor: it is what every panel that answers at all can serve, and
  // the guide only offers what the window covers.
  return enabled ? 1 : null;
}

/// Category id → name, for `get_live_categories`.
Map<String, String> categoriesFromXtream(List<dynamic> rows) {
  final names = <String, String>{};
  for (final row in rows) {
    if (row is! Map) continue;
    final id = _string(row['category_id']);
    final name = _string(row['category_name']);
    if (id != null && name != null) names[id] = name;
  }
  return names;
}

/// Map `get_short_epg` rows onto programmes for [channel].
///
/// Titles and descriptions come base64-encoded, and the timestamps arrive
/// either as epoch seconds (`start_timestamp`) or as a formatted local string.
/// Rows whose time cannot be read are dropped: a programme without a slot
/// cannot be placed in a guide.
List<LiveTvProgram> programsFromXtreamEpg(List<dynamic> rows, {required LiveTvChannel channel}) {
  final programs = <LiveTvProgram>[];

  for (final row in rows) {
    if (row is! Map) continue;
    final begins = _epochSeconds(row['start_timestamp']) ?? _epochSecondsFromText(_string(row['start']));
    final ends = _epochSeconds(row['stop_timestamp']) ?? _epochSecondsFromText(_string(row['end']));
    if (begins == null || ends == null) continue;

    programs.add(
      LiveTvProgram(
        key: 'iptv:${channel.key}:$begins',
        title: _decodeMaybeBase64(_string(row['title'])) ?? '',
        summary: _decodeMaybeBase64(_string(row['description'])),
        beginsAt: begins,
        endsAt: ends,
        channelIdentifier: channel.identifier,
        channelCallSign: channel.callSign,
        serverId: channel.serverId,
        serverName: channel.serverName,
      ),
    );
  }

  programs.sort((a, b) => (a.beginsAt ?? 0).compareTo(b.beginsAt ?? 0));
  return programs;
}

String? _string(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _epochSeconds(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// `"2024-05-04 20:15:00"`, which the panel reports in its own timezone.
int? _epochSecondsFromText(String? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
  return parsed == null ? null : parsed.millisecondsSinceEpoch ~/ 1000;
}

/// Xtream base64-encodes EPG text, but not every panel does. Decoding is
/// therefore attempted and abandoned unless the payload both looks like base64
/// and decodes to valid UTF-8 — a plain title like "Tagesschau" is neither.
String? _decodeMaybeBase64(String? value) {
  if (value == null) return null;
  if (value.length % 4 != 0 || !RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(value)) return value;
  try {
    final decoded = utf8.decode(base64.decode(value));
    return decoded.trim().isEmpty ? value : decoded;
  } on FormatException {
    return value;
  }
}
