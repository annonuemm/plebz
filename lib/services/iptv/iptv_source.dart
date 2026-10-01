import 'dart:convert';

import 'iptv_catchup.dart';

/// How an IPTV source is reached.
enum IptvSourceKind {
  /// An extended M3U playlist, optionally paired with an XMLTV guide.
  m3u,

  /// An Xtream Codes panel, which serves both channels and guide over its
  /// own JSON API.
  xtream,
}

/// The container an Xtream panel is asked to serve a live channel in.
///
/// Both are standard on every panel and carry the same picture. The transport
/// stream is what most IPTV players ask for and what more panels serve
/// correctly; the HLS form is segmented, which some proxies handle better and
/// which allows a small seek back into the buffer.
enum IptvStreamFormat {
  mpegTs('ts'),
  hls('m3u8');

  const IptvStreamFormat(this.extension);

  /// The extension the panel's live path ends in.
  final String extension;
}

/// The fields of a stored source that are credentials and sealed at rest
/// (`IptvSourcesProvider`): the panel password, and the playlist and guide
/// addresses, which for most M3U providers carry the login themselves.
const iptvSealedFields = ['password', 'playlistUrl', 'epgUrls'];

/// One configured IPTV source.
///
/// Deliberately not a media server: it carries no library, no watch state and
/// no recordings — only what is needed to list channels, read a guide and open
/// a stream.
class IptvSource {
  const IptvSource({
    required this.id,
    required this.name,
    required this.kind,
    this.playlistUrl,
    this.epgUrls = const [],
    this.baseUrl,
    this.username,
    this.password,
    this.streamFormat = IptvStreamFormat.mpegTs,
    this.catchupMode = IptvCatchupMode.automatic,
    this.catchupDays,
  });

  /// Stable id, also used to namespace channel keys and favorites.
  final String id;

  /// User-facing name, shown wherever a channel's origin is named.
  final String name;

  final IptvSourceKind kind;

  /// [IptvSourceKind.m3u]: where the playlist lives.
  final String? playlistUrl;

  /// XMLTV guides, merged in order. More than one because no single guide
  /// covers every channel a playlist carries — the second list fills the
  /// holes in the first. An Xtream panel may carry these too, on top of the
  /// guide it serves itself.
  final List<String> epgUrls;

  /// [IptvSourceKind.xtream]: panel root and credentials.
  final String? baseUrl;
  final String? username;
  final String? password;

  /// [IptvSourceKind.xtream]: which container to ask the panel for. Unused
  /// for a playlist, whose entries carry their own URLs.
  final IptvStreamFormat streamFormat;

  /// How this provider addresses its archive. Left on
  /// [IptvCatchupMode.automatic] the source is taken at its word; the explicit
  /// modes are for providers that ship an archive without declaring one, or
  /// declare one shape and serve another.
  final IptvCatchupMode catchupMode;

  /// How far back the archive goes, when the provider does not say. Panels
  /// report it per channel (`tv_archive_duration`) and playlists in
  /// `catchup-days`; this fills in for the ones that report neither.
  final int? catchupDays;

  /// Whether this source has everything it needs to be queried.
  bool get isComplete => switch (kind) {
    IptvSourceKind.m3u => (playlistUrl?.trim().isNotEmpty ?? false),
    IptvSourceKind.xtream =>
      (baseUrl?.trim().isNotEmpty ?? false) &&
          (username?.trim().isNotEmpty ?? false) &&
          (password?.trim().isNotEmpty ?? false),
  };

  IptvSource copyWith({
    String? name,
    IptvSourceKind? kind,
    String? playlistUrl,
    List<String>? epgUrls,
    String? baseUrl,
    String? username,
    String? password,
    IptvStreamFormat? streamFormat,
    IptvCatchupMode? catchupMode,
    int? catchupDays,
  }) => IptvSource(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    playlistUrl: playlistUrl ?? this.playlistUrl,
    epgUrls: epgUrls ?? this.epgUrls,
    baseUrl: baseUrl ?? this.baseUrl,
    username: username ?? this.username,
    password: password ?? this.password,
    streamFormat: streamFormat ?? this.streamFormat,
    catchupMode: catchupMode ?? this.catchupMode,
    catchupDays: catchupDays ?? this.catchupDays,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    if (playlistUrl != null) 'playlistUrl': playlistUrl,
    if (epgUrls.isNotEmpty) 'epgUrls': epgUrls,
    if (baseUrl != null) 'baseUrl': baseUrl,
    if (username != null) 'username': username,
    if (password != null) 'password': password,
    'streamFormat': streamFormat.name,
    'catchupMode': catchupMode.name,
    if (catchupDays != null) 'catchupDays': catchupDays,
  };

  static IptvSource? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    final kind = IptvSourceKind.values.asNameMap()[json['kind']];
    if (kind == null) return null;

    String? text(Object? value) => value is String && value.isNotEmpty ? value : null;

    // `epgUrl` is the single-guide shape this fork stored first; a source
    // saved then must not lose its guide.
    final storedUrls = json['epgUrls'];
    final epgUrls = <String>[
      if (storedUrls is List)
        for (final entry in storedUrls) ?text(entry)
      else
        ?text(json['epgUrl']),
    ];

    return IptvSource(
      id: id,
      name: name,
      kind: kind,
      playlistUrl: text(json['playlistUrl']),
      epgUrls: epgUrls,
      baseUrl: text(json['baseUrl']),
      username: text(json['username']),
      password: text(json['password']),
      // Sources saved before the choice existed were served HLS, which is
      // what the app asked for unconditionally.
      streamFormat: IptvStreamFormat.values.asNameMap()[json['streamFormat']] ?? IptvStreamFormat.hls,
      catchupMode: IptvCatchupMode.values.asNameMap()[json['catchupMode']] ?? IptvCatchupMode.automatic,
      catchupDays: switch (json['catchupDays']) {
        final int days when days > 0 => days,
        final String days => int.tryParse(days),
        _ => null,
      },
    );
  }

  static String encodeList(List<IptvSource> sources) => jsonEncode([for (final source in sources) source.toJson()]);

  /// Tolerant decode: a malformed entry is skipped rather than costing the
  /// user every configured source.
  static List<IptvSource> decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map<String, Object?>) ?fromJson(entry),
      ];
    } on FormatException {
      return const [];
    }
  }
}
