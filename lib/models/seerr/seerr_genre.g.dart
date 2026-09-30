// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seerr_genre.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SeerrGenre _$SeerrGenreFromJson(Map<String, dynamic> json) => SeerrGenre(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  backdrops:
      (json['backdrops'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      [],
);
