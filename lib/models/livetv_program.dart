import '../i18n/strings.g.dart';
import '../utils/json_utils.dart';
import '../media/ids.dart';

/// Represents an EPG program entry (what's on a channel at a given time)
class LiveTvProgram {
  final String? key;
  final String? ratingKey;
  final String? guid;
  final String title;

  /// A second title line: XMLTV `<sub-title>`, Jellyfin's `EpisodeTitle`.
  /// A sports guide often puts the pairing here under a title that only
  /// names the competition ("Bundesliga" / "Borussia Dortmund - Werder
  /// Bremen"), which is where the Sport page looks for it.
  final String? subtitle;
  final String? summary;
  final String? type;
  final int? year;

  /// Genres as the guide states them — XMLTV `<category>`, one entry per tag.
  ///
  /// Kept apart from [summary] because many providers also glue them to the
  /// front of the description, without a separator: "…Deutschland 2019Tragikomödie
  /// eines Mannes…". Read from their own field, they can be set on their own line.
  final List<String>? genres;

  /// XMLTV `<country>`.
  final String? country;
  final int? beginsAt; // epoch seconds
  final int? endsAt; // epoch seconds
  final String? grandparentTitle; // series name for episodes
  final String? parentTitle; // season name
  final int? index; // episode number
  final int? parentIndex; // season number
  final String? thumb;
  final String? art;
  final String? channelIdentifier;
  final String? channelCallSign;
  final bool? live;
  final bool? premiere;

  /// Recording-rule key targeting this airing directly (`subscriptionID`).
  /// Plex stamps subscribed airings in the grid/metadata responses themselves;
  /// the official client derives its "scheduled" state from these attributes.
  final String? subscriptionId;

  /// Recording-rule key targeting this airing's show (`grandparentSubscriptionID`).
  final String? grandparentSubscriptionId;
  final String? serverId;
  final String? serverName;
  final String? liveDvrKey;
  final String? providerIdentifier;

  LiveTvProgram({
    this.key,
    this.ratingKey,
    this.guid,
    required this.title,
    this.subtitle,
    this.summary,
    this.type,
    this.year,
    this.genres,
    this.country,
    this.beginsAt,
    this.endsAt,
    this.grandparentTitle,
    this.parentTitle,
    this.index,
    this.parentIndex,
    this.thumb,
    this.art,
    this.channelIdentifier,
    this.channelCallSign,
    this.live,
    this.premiere,
    this.subscriptionId,
    this.grandparentSubscriptionId,
    this.serverId,
    this.serverName,
    this.liveDvrKey,
    this.providerIdentifier,
  });

  factory LiveTvProgram.fromJson(Map<String, dynamic> json, {Map<String, dynamic>? mediaOverride}) {
    // Grid endpoint nests timing/channel info inside Media[] and Channel[].
    // When mediaOverride is supplied, the caller is pinning this parse to a
    // specific airing (one Media entry); treat it as authoritative for
    // begin/end/channel fields.
    final hasOverride = mediaOverride != null;
    final media = mediaOverride ?? (json['Media'] as List?)?.firstOrNull as Map<String, dynamic>?;
    final channel = (json['Channel'] as List?)?.firstOrNull as Map<String, dynamic>?;

    int? pickInt(String key) {
      final fromMedia = flexibleInt(media?[key]);
      final fromJson = flexibleInt(json[key]);
      return hasOverride ? (fromMedia ?? fromJson) : (fromJson ?? fromMedia);
    }

    String? pickString(String key) {
      final fromMedia = media?[key]?.toString();
      final fromJson = json[key] as String?;
      return hasOverride ? (fromMedia ?? fromJson) : (fromJson ?? fromMedia);
    }

    return LiveTvProgram(
      key: json['key'] as String?,
      ratingKey: json['ratingKey'] as String?,
      guid: json['guid'] as String?,
      title: json['title'] as String? ?? t.liveTv.unknownProgram,
      subtitle: json['subtitle'] as String?,
      summary: json['summary'] as String?,
      type: json['type'] as String?,
      year: flexibleInt(json['year']),
      genres: (json['genres'] as List?)?.whereType<String>().toList(),
      country: json['country'] as String?,
      beginsAt: pickInt('beginsAt'),
      endsAt: pickInt('endsAt'),
      grandparentTitle: json['grandparentTitle'] as String?,
      parentTitle: json['parentTitle'] as String?,
      index: flexibleInt(json['index']),
      parentIndex: flexibleInt(json['parentIndex']),
      thumb: json['thumb'] as String? ?? json['grandparentThumb'] as String?,
      art: json['art'] as String?,
      channelIdentifier: pickString('channelIdentifier') ?? channel?['id']?.toString(),
      channelCallSign: pickString('channelCallSign'),
      live: flexibleBool(json['live']),
      premiere: flexibleBool(json['premiere']),
      // Set after parsing everywhere a server is involved; read here so a
      // programme written to the IPTV cache comes back belonging to its
      // source. No server sends these keys.
      serverId: json['serverId'] as String?,
      serverName: json['serverName'] as String?,
      liveDvrKey: json['liveDvrKey'] as String?,
      providerIdentifier: json['providerIdentifier'] as String?,
      subscriptionId: json['subscriptionID']?.toString(),
      grandparentSubscriptionId: json['grandparentSubscriptionID']?.toString(),
    );
  }

  /// The whole programme, for the IPTV cache. Every key is one [fromJson]
  /// reads, so this round-trips.
  Map<String, dynamic> toJson() => {
    if (key != null) 'key': key,
    if (ratingKey != null) 'ratingKey': ratingKey,
    if (guid != null) 'guid': guid,
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (summary != null) 'summary': summary,
    if (type != null) 'type': type,
    if (year != null) 'year': year,
    if (genres != null && genres!.isNotEmpty) 'genres': genres,
    if (country != null) 'country': country,
    if (beginsAt != null) 'beginsAt': beginsAt,
    if (endsAt != null) 'endsAt': endsAt,
    if (grandparentTitle != null) 'grandparentTitle': grandparentTitle,
    if (parentTitle != null) 'parentTitle': parentTitle,
    if (index != null) 'index': index,
    if (parentIndex != null) 'parentIndex': parentIndex,
    if (thumb != null) 'thumb': thumb,
    if (art != null) 'art': art,
    if (channelIdentifier != null) 'channelIdentifier': channelIdentifier,
    if (channelCallSign != null) 'channelCallSign': channelCallSign,
    if (live != null) 'live': live,
    if (premiere != null) 'premiere': premiere,
    if (serverId != null) 'serverId': serverId,
    if (serverName != null) 'serverName': serverName,
    if (liveDvrKey != null) 'liveDvrKey': liveDvrKey,
    if (providerIdentifier != null) 'providerIdentifier': providerIdentifier,
  };

  LiveTvProgram copyWith({
    ServerId? serverId,
    String? serverName,
    String? liveDvrKey,
    String? providerIdentifier,
    int? endsAt,
  }) {
    return LiveTvProgram(
      key: key,
      ratingKey: ratingKey,
      guid: guid,
      title: title,
      subtitle: subtitle,
      summary: summary,
      type: type,
      year: year,
      genres: genres,
      country: country,
      beginsAt: beginsAt,
      endsAt: endsAt ?? this.endsAt,
      grandparentTitle: grandparentTitle,
      parentTitle: parentTitle,
      index: index,
      parentIndex: parentIndex,
      thumb: thumb,
      art: art,
      channelIdentifier: channelIdentifier,
      channelCallSign: channelCallSign,
      live: live,
      premiere: premiere,
      subscriptionId: subscriptionId,
      grandparentSubscriptionId: grandparentSubscriptionId,
      serverId: serverId ?? this.serverId,
      serverName: serverName ?? this.serverName,
      liveDvrKey: liveDvrKey ?? this.liveDvrKey,
      providerIdentifier: providerIdentifier ?? this.providerIdentifier,
    );
  }

  /// Key of the recording rule covering this airing, or null when the server
  /// did not tag it as subscribed. The show-level rule wins over an item-level
  /// one, matching how the official client resolves these attributes.
  String? get recordingRuleKey {
    final show = grandparentSubscriptionId?.trim();
    if (show != null && show.isNotEmpty) return show;
    final item = subscriptionId?.trim();
    if (item != null && item.isNotEmpty) return item;
    return null;
  }

  DateTime? get startTime => beginsAt != null ? DateTime.fromMillisecondsSinceEpoch(beginsAt! * 1000) : null;

  DateTime? get endTime => endsAt != null ? DateTime.fromMillisecondsSinceEpoch(endsAt! * 1000) : null;

  int get durationMinutes {
    if (beginsAt == null || endsAt == null) return 0;
    return ((endsAt! - beginsAt!) / 60).round();
  }

  bool get isCurrentlyAiring {
    if (beginsAt == null || endsAt == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= beginsAt! && now < endsAt!;
  }

  double get progress {
    if (beginsAt == null || endsAt == null) return 0.0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now < beginsAt!) return 0.0;
    if (now >= endsAt!) return 1.0;
    return (now - beginsAt!) / (endsAt! - beginsAt!);
  }

  String get displayTitle {
    if (grandparentTitle != null && index != null) {
      final seasonEpisode = parentIndex != null ? 'S${parentIndex}E$index' : 'E$index';
      return '$grandparentTitle - $seasonEpisode - $title';
    }
    return title;
  }
}
