import 'package:json_annotation/json_annotation.dart';

import '../utils/json_utils.dart';

part 'media_role.g.dart';

/// A cast or crew member attached to a media item.
@JsonSerializable(includeIfNull: false)
class MediaRole {
  final String? id;
  @JsonKey(fromJson: stringOrEmpty)
  final String tag;
  final String? role;
  final String? thumbPath;

  /// Plex Discover's id for the person — a Plex server's `tagKey` — where the
  /// server names one; it opens their Plex filmography without a name search
  /// (Plebz).
  final String? discoverId;

  const MediaRole({this.id, required this.tag, this.role, this.thumbPath, this.discoverId});

  factory MediaRole.fromJson(Map<String, dynamic> json) => _$MediaRoleFromJson(json);

  Map<String, dynamic> toJson() => _$MediaRoleToJson(this);
}
