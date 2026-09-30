// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'livetv_channel.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LiveTvChannel _$LiveTvChannelFromJson(Map<String, dynamic> json) =>
    LiveTvChannel(
      key: _readChannelKey(json, 'key') as String,
      identifier: _readChannelIdentifier(json, 'identifier') as String?,
      callSign: json['callSign'] as String?,
      title: _readChannelTitle(json, 'title') as String?,
      thumb: json['thumb'] as String?,
      art: json['art'] as String?,
      number: _readChannelNumber(json, 'number') as String?,
      hd: json['hd'] == null ? false : flexibleBool(json['hd']),
      lineup: json['lineup'] as String?,
      slug: json['slug'] as String?,
      drm: flexibleBool(json['drm']),
      serverId: json['serverId'] as String?,
      serverName: json['serverName'] as String?,
      liveDvrKey: json['liveDvrKey'] as String?,
      liveTvSourceTitle: json['liveTvSourceTitle'] as String?,
      favoriteSource: json['favoriteSource'] as String?,
      favoriteStoreKey: json['favoriteStoreKey'] as String?,
      catchupDays: (json['catchupDays'] as num?)?.toInt(),
    );

Map<String, dynamic> _$LiveTvChannelToJson(LiveTvChannel instance) =>
    <String, dynamic>{
      'key': instance.key,
      'identifier': instance.identifier,
      'callSign': instance.callSign,
      'title': instance.title,
      'thumb': instance.thumb,
      'art': instance.art,
      'number': instance.number,
      'hd': instance.hd,
      'lineup': instance.lineup,
      'slug': instance.slug,
      'drm': instance.drm,
      'serverId': instance.serverId,
      'serverName': instance.serverName,
      'liveDvrKey': instance.liveDvrKey,
      'liveTvSourceTitle': instance.liveTvSourceTitle,
      'favoriteSource': instance.favoriteSource,
      'favoriteStoreKey': instance.favoriteStoreKey,
      'catchupDays': instance.catchupDays,
    };

FavoriteChannel _$FavoriteChannelFromJson(Map<String, dynamic> json) =>
    FavoriteChannel(
      source: json['source'] as String? ?? '',
      id: _readFavoriteChannelId(json, 'id') as String,
      title: json['title'] as String?,
      thumb: json['thumb'] as String?,
      vcn: json['vcn'] as String?,
    );
