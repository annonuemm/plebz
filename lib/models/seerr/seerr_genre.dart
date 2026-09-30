import 'package:json_annotation/json_annotation.dart';

part 'seerr_genre.g.dart';

/// One entry of Seerr's genre slider (`/discover/genreslider/movie|tv`).
///
/// [backdrops] are the collage Seerr's own web front end paints a genre tile
/// with; they are TMDB backdrop paths, not full URLs.
@JsonSerializable(createToJson: false)
class SeerrGenre {
  final int id;
  final String name;
  @JsonKey(defaultValue: <String>[])
  final List<String> backdrops;

  const SeerrGenre({required this.id, required this.name, this.backdrops = const []});

  factory SeerrGenre.fromJson(Map<String, dynamic> json) => _$SeerrGenreFromJson(json);
}
