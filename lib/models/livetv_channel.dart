import 'package:json_annotation/json_annotation.dart';

import '../i18n/strings.g.dart';
import '../utils/json_utils.dart';

part 'livetv_channel.g.dart';

Object? _readChannelKey(Map json, String _) =>
    json['key'] as String? ??
    json['ratingKey'] as String? ??
    json['identifier'] as String? ??
    json['id'] as String? ??
    json['channelIdentifier'] as String? ??
    '';

Object? _readChannelIdentifier(Map json, String _) =>
    json['identifier'] as String? ?? json['id'] as String? ?? json['channelIdentifier'] as String?;

Object? _readChannelTitle(Map json, String _) => json['title'] as String? ?? json['callSign'] as String?;

Object? _readChannelNumber(Map json, String _) =>
    json['number'] as String? ??
    json['channelNumber'] as String? ??
    json['channelVcn']?.toString() ??
    json['vcn']?.toString();

Object? _readFavoriteChannelId(Map json, String _) => json['id'] as String? ?? json['key'] as String? ?? '';

String favoriteChannelKey(String source, String id) => '$source\u0000$id';

String liveTvChannelScopeKey(LiveTvChannel channel) =>
    '${channel.serverId ?? ''}\u0000${channel.liveDvrKey ?? ''}\u0000${channel.key}';

List<LiveTvChannel> filterLiveTvChannelsForFavorites({
  required List<LiveTvChannel> channels,
  required bool favoritesOnly,
  required bool favoritesLoaded,
  required Iterable<FavoriteChannel> favorites,
  required String Function(LiveTvChannel channel) sourceForChannel,
}) {
  if (!favoritesOnly || !favoritesLoaded) return channels;
  if (favorites.isEmpty) return const [];
  final channelMap = {
    for (final channel in channels) favoriteChannelKey(sourceForChannel(channel), channel.key): channel,
  };

  return [for (final favorite in favorites) ?channelMap[favorite.stableKey]];
}

/// Serialized in both directions: the incoming shapes come from the servers
/// (hence the [JsonKey.readValue] hooks, which all read the plain key first),
/// and the outgoing one is what the IPTV cache keeps on disk. The fields a
/// server never sends are written too — they are set after parsing, and a
/// restored channel without them belongs to no source.
@JsonSerializable()
class LiveTvChannel {
  @JsonKey(readValue: _readChannelKey)
  final String key;
  @JsonKey(readValue: _readChannelIdentifier)
  final String? identifier;
  final String? callSign;
  @JsonKey(readValue: _readChannelTitle)
  final String? title;
  final String? thumb;
  final String? art;
  @JsonKey(readValue: _readChannelNumber)
  final String? number;
  @JsonKey(fromJson: flexibleBool)
  final bool hd;
  final String? lineup;
  final String? slug;
  @JsonKey(fromJson: flexibleBool)
  final bool? drm;

  final String? serverId;
  final String? serverName;
  final String? liveDvrKey;
  final String? liveTvSourceTitle;
  final String? favoriteSource;
  final String? favoriteStoreKey;

  /// How many days of archive this channel has, for the IPTV providers that
  /// serve one. Null means no archive — which is every channel a media server
  /// serves, and most of a playlist's.
  final int? catchupDays;

  /// The logo an IPTV guide names for this channel, where the playlist's own
  /// is there but may not load — the next one [LiveTvChannelLogo] tries.
  /// Set after parsing and never stored: the guide's logos are kept with the
  /// guide.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String? guideLogo;

  /// The name the viewer gave this channel, laid on by the channel
  /// arrangement (see `applyLiveTvChannelLayout`) and shown wherever the
  /// channel is named. Never stored with the channel: the arrangement keeps it.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String? nameOverride;

  LiveTvChannel({
    required this.key,
    this.identifier,
    this.callSign,
    this.title,
    this.thumb,
    this.art,
    this.number,
    this.hd = false,
    this.lineup,
    this.slug,
    this.drm,
    this.serverId,
    this.serverName,
    this.liveDvrKey,
    this.liveTvSourceTitle,
    this.favoriteSource,
    this.favoriteStoreKey,
    this.catchupDays,
    this.guideLogo,
    this.nameOverride,
  });

  factory LiveTvChannel.fromJson(Map<String, dynamic> json) => _$LiveTvChannelFromJson(json);

  Map<String, dynamic> toJson() => _$LiveTvChannelToJson(this);

  LiveTvChannel copyWith({
    String? thumb,
    String? guideLogo,
    String? serverId,
    String? serverName,
    String? liveDvrKey,
    String? liveTvSourceTitle,
    String? favoriteSource,
    String? favoriteStoreKey,
    int? catchupDays,
    String? nameOverride,
  }) {
    return LiveTvChannel(
      key: key,
      identifier: identifier,
      callSign: callSign,
      title: title,
      thumb: thumb ?? this.thumb,
      art: art,
      number: number,
      hd: hd,
      lineup: lineup,
      slug: slug,
      drm: drm,
      serverId: serverId ?? this.serverId,
      serverName: serverName ?? this.serverName,
      liveDvrKey: liveDvrKey ?? this.liveDvrKey,
      liveTvSourceTitle: liveTvSourceTitle ?? this.liveTvSourceTitle,
      favoriteSource: favoriteSource ?? this.favoriteSource,
      favoriteStoreKey: favoriteStoreKey ?? this.favoriteStoreKey,
      catchupDays: catchupDays ?? this.catchupDays,
      guideLogo: guideLogo ?? this.guideLogo,
      nameOverride: nameOverride ?? this.nameOverride,
    );
  }

  /// What the channel is called on screen: the viewer's own name for it, or
  /// else the provider's ([sourceName]).
  String get displayName => nameOverride ?? sourceName;

  /// The provider's name for the channel: its call sign, else its title. What
  /// anything that *recognises* a channel by name reads — the Sport
  /// broadcaster match among them — since a name the viewer chose says nothing
  /// about what the channel carries.
  String get sourceName =>
      callSign ?? title ?? (number == null ? t.liveTv.unknownChannel : t.liveTv.channelNumber(number: number!));
}

/// A channel entry in the Plex cloud favorites list.
/// Stored at `https://epg.provider.plex.tv/settings/favoriteChannels`.
@JsonSerializable(createToJson: false)
class FavoriteChannel {
  @JsonKey(defaultValue: '')
  final String source;
  @JsonKey(readValue: _readFavoriteChannelId)
  final String id;
  final String? title;
  final String? thumb;
  final String? vcn;

  FavoriteChannel({required this.source, required this.id, this.title, this.thumb, this.vcn});

  factory FavoriteChannel.fromJson(Map<String, dynamic> json) => _$FavoriteChannelFromJson(json);

  String get stableKey => favoriteChannelKey(source, id);

  Map<String, dynamic> toJson() => {
    'source': source,
    'id': id,
    if (title != null) 'title': title,
    if (thumb != null) 'thumb': thumb,
    if (vcn != null) 'vcn': vcn,
  };

  /// Create from a [LiveTvChannel] and a source URI.
  factory FavoriteChannel.fromLiveTvChannel(LiveTvChannel channel, String source) {
    return FavoriteChannel(
      source: source,
      id: channel.key,
      title: channel.title ?? channel.callSign,
      thumb: channel.thumb,
      vcn: channel.number,
    );
  }
}
