/// One entry of a catalog item's cast section: an actor with their character
/// (Trakt) or an anime character with its role (MAL).
class CatalogCastMember {
  final String name;

  /// Character name (Trakt) or role such as `Main` / `Supporting` (MAL).
  final String? secondary;

  /// Absolute https headshot/portrait URL.
  final String? imageUrl;

  /// Plex Discover's id for this person, where the source is Plex; it opens
  /// their filmography without a name search (Plebz).
  final String? personId;

  const CatalogCastMember({required this.name, this.secondary, this.imageUrl, this.personId});

  Map<String, Object?> toJson() => {
    'name': name,
    if (secondary != null) 'secondary': secondary,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (personId != null) 'personId': personId,
  };

  static CatalogCastMember? fromJson(Map<String, Object?> json) {
    final name = json['name'] as String?;
    if (name == null) return null;
    return CatalogCastMember(
      name: name,
      secondary: json['secondary'] as String?,
      imageUrl: json['imageUrl'] as String?,
      personId: json['personId'] as String?,
    );
  }
}
