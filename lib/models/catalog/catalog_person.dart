import 'catalog_item.dart';

/// A person as Plex Discover knows them: what their page shows above the
/// filmography (Plebz).
class CatalogPerson {
  final String id;
  final String name;

  /// Absolute https portrait URL.
  final String? thumbUrl;

  /// The biography, in the app's language where Discover has one.
  final String? summary;
  final DateTime? bornAt;
  final DateTime? diedAt;
  final String? birthPlace;

  /// Discover's departments for the person, most credits first: `actor`,
  /// `director`, `producer`, `writer`, …
  final List<String> departments;

  /// The department Discover leads with, in its own words ("Acting").
  final String? knownFor;

  const CatalogPerson({
    required this.id,
    required this.name,
    this.thumbUrl,
    this.summary,
    this.bornAt,
    this.diedAt,
    this.birthPlace,
    this.departments = const [],
    this.knownFor,
  });
}

/// One title in a person's filmography, with what they were in it.
class CatalogPersonCredit {
  final CatalogItem item;

  /// The character, or the job for a crew credit; null where none is named.
  final String? role;

  /// Discover's group for the credit: `actor`, `producer`, `appeared`, …
  final String group;

  const CatalogPersonCredit({required this.item, this.role, required this.group});

  /// Guest spots as themselves — talk shows, award nights. Listed after the
  /// work proper, as Plex keeps them on a tab of their own.
  bool get isAppearance => group == 'appeared';
}
