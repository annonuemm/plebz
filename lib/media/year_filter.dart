import 'media_hub.dart';
import 'media_item.dart';
import 'media_kind.dart';

/// A closed or half-open range of release years.
///
/// Both ends are optional: "from 1985" with no end means up to whatever comes
/// out next, and an empty range filters nothing at all. Zero stands for "not
/// set" because that is how the setting stores an empty field.
class YearRange {
  const YearRange({this.from, this.to});

  final int? from;
  final int? to;

  static const YearRange none = YearRange();

  bool get isEmpty => from == null && to == null;

  /// Whether a title from [year] belongs. A title whose year the server never
  /// supplied is kept: an unknown year is not evidence of the wrong year, and
  /// hiding it would make the library look damaged.
  bool allows(int? year) {
    if (isEmpty || year == null) return true;
    if (from != null && year < from!) return false;
    if (to != null && year > to!) return false;
    return true;
  }

  /// The range written out, which is the only form the servers take: Plex
  /// wants `year=1985,1986,…` and Jellyfin `Years=…`, and neither has an
  /// operator for "or later".
  ///
  /// [upperBound] closes an open end — the current year, plus one because a
  /// library carries titles announced for next year.
  List<int> years({required int upperBound, int lowerBound = 1900}) {
    if (isEmpty) return const [];
    final start = from ?? lowerBound;
    final end = to ?? upperBound;
    if (end < start) return const [];
    return [for (var year = start; year <= end; year++) year];
  }

  @override
  bool operator ==(Object other) => other is YearRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'YearRange(${from ?? '…'}–${to ?? '…'})';
}

/// A stored pair of years as a range. Zero and negative values mean "not set",
/// and a pair the wrong way round is read as the range the user meant rather
/// than as an empty one — nobody types 2010–1997 to see nothing.
YearRange yearRangeFrom(int from, int to) {
  final start = from > 0 ? from : null;
  final end = to > 0 ? to : null;
  if (start != null && end != null && end < start) return YearRange(from: end, to: start);
  return YearRange(from: start, to: end);
}

/// Which kinds the series range speaks for.
bool isSeriesLikeKind(MediaKind kind) =>
    kind == MediaKind.show || kind == MediaKind.season || kind == MediaKind.episode;

/// Whether [item] passes the range that applies to its kind.
///
/// Anything that is neither film nor series — music, photos, live channels —
/// is left alone: a year range on a record collection is not what was asked
/// for, and silently thinning one would be a bug nobody could explain.
bool yearFilterAllowsItem(MediaItem item, {required YearRange movies, required YearRange shows}) {
  final kind = item.kind;
  // A season or an episode carries its own air year, and a series that ran
  // for a decade would be cut in half by it — the 1999 show whose fourth
  // season aired in 2005 is still the 1999 show. What a series belongs to is
  // decided on the series, and everything under it follows.
  if (kind == MediaKind.season || kind == MediaKind.episode) return true;
  if (kind == MediaKind.show) return shows.allows(item.year);
  if (kind == MediaKind.movie) return movies.allows(item.year);
  return true;
}

/// [hub] with the titles the ranges leave out removed.
///
/// Used where rows are shown outside the libraries, which the servers cannot
/// filter for us — a home shelf comes back as it comes back. A row that ends
/// up empty is handed back empty for the caller to drop, rather than left as
/// a heading over nothing.
MediaHub applyYearFilterToHub(MediaHub hub, {required YearRange movies, required YearRange shows}) {
  if (movies.isEmpty && shows.isEmpty) return hub;
  final kept = [
    for (final item in hub.items)
      if (yearFilterAllowsItem(item, movies: movies, shows: shows)) item,
  ];
  if (kept.length == hub.items.length) return hub;
  return hub.copyWith(items: kept, size: kept.length);
}
