import '../utils/resolution_label.dart';
import '../utils/search_relevance.dart' show normalizeSearchText;
import 'media_backend.dart';
import 'media_item.dart';
import 'media_item_merge.dart';
import 'media_kind.dart';

/// One title, and every copy of it the search found.
///
/// [best] is the copy a result row stands for and the one OK opens — the
/// highest resolution, by [compareLibraryCopies]. [copies] holds all of them,
/// that one included, in the same order.
typedef MediaSearchGroup = ({MediaItem best, List<MediaItem> copies});

/// Separates the parts of an identity key. Not a character any of them holds.
const String _sep = '\u0000';

/// Fold the copies of one title into one result.
///
/// A search across servers returns a row per *file*, not per title: the same
/// film sits in a 1080p library and a 4K library and an original-language
/// library, and every one of them comes back. They then score identically, so
/// they land next to each other, and between them they spend the result budget
/// several times over on one thing.
///
/// Identity is decided from what the search rows already carry, because
/// anything else costs a request per row:
///
///  - **A matching Plex guid is exact.** Every copy of a film on a Plex server
///    carries the agent's guid for it, whatever library it is filed in. This
///    is the case that matters most, since a 1080p and a 4K library are
///    usually two libraries on one server.
///
///    Plex only. `MediaItem.guid` is a Plex idea; the Jellyfin mapper fills
///    the same field with the item's own id, which is unique per *file* —
///    trusting it there gave every Jellyfin copy a group of its own and folded
///    nothing at all.
///  - **A matching provider id is exact too.** Jellyfin's search rows now ask
///    for `ProviderIds`, so two copies of one film in two Jellyfin libraries
///    agree on a TMDB or IMDb id and fold on it rather than on their names.
///    It does not reach across backends: a current Plex guid is an opaque
///    agent hash and carries no TMDB id to compare against.
///  - **Otherwise: kind, title and year, and only where the year is there on
///    both sides.** What is left when neither side offered an id — an old
///    Plex library, a Jellyfin item nothing has matched. It is a guess, so it
///    is made narrowly: no year, no merge. Two rows too many is a nuisance; a
///    wrong merge hides a title the viewer owns.
///
/// An unmatched file (Plex's personal-media agent) carries a guid unique to
/// itself, so it never merges with anything — which is right: nothing about it
/// says it is the same work as the file beside it.
List<MediaSearchGroup> groupMediaSearchCopies(List<MediaItem> items) {
  if (items.isEmpty) return const [];

  final byIdentity = <String, List<MediaItem>>{};
  final order = <String>[];
  for (final item in items) {
    final key = _identityKey(item);
    final bucket = byIdentity.putIfAbsent(key, () {
      order.add(key);
      return <MediaItem>[];
    });
    bucket.add(item);
  }

  final groups = <MediaSearchGroup>[];
  for (final key in order) {
    final copies = byIdentity[key]!..sort(compareLibraryCopies);
    groups.add((best: copies.first, copies: copies));
  }
  return groups;
}

/// Kind, title and year — what two rows from different places have in common
/// when they have nothing else.
///
/// Null where the evidence is missing, and a null must never be treated as a
/// match: a row without a year is not the same thing as another row without a
/// year. Used to tell an owned title apart from a catalogue entry for it,
/// where no id is shared by both sides.
String? mediaSearchTitleKey(MediaItem item) {
  final title = normalizeSearchText(item.title);
  final year = item.year;
  if (title.isEmpty || year == null) return null;
  return 'ty$_sep${item.kind.id}$_sep$title$_sep$year';
}

String _identityKey(MediaItem item) {
  final guid = item.guid;
  // See the note above: on Jellyfin this field is the item's own id.
  if (item.backend == MediaBackend.plex && guid != null && guid.isNotEmpty) return 'guid$_sep$guid';

  // The kind rides along: a film and a series can hold the same TMDB id, and
  // a folded pair of those would be a page that opens the wrong thing.
  if (_providerId(item) case final id?) return 'pid$_sep${item.kind.id}$_sep$id';

  final title = normalizeSearchText(item.title);
  final year = item.year;
  if (title.isEmpty || year == null) return 'self$_sep${item.globalKey}';

  // An episode's title repeats across series and seasons far more often than a
  // film's does, so where it sits in the run is part of who it is.
  final place = item.kind == MediaKind.episode
      ? '$_sep${normalizeSearchText(item.grandparentTitle)}$_sep${item.parentIndex}$_sep${item.index}'
      : '';
  return 'ty$_sep${item.kind.id}$_sep$title$_sep$year$place';
}

/// What a row says about the copies behind it: `4K · 1080p`, or `2 × 1080p`
/// where a resolution is there more than once.
///
/// Best first, because [copies] arrives sorted that way and the best copy is
/// the one the row opens. The count is only written where it is more than one:
/// "1 ×" in front of every entry is a column of ones that says nothing.
///
/// Where a copy cannot say what it is, the label names the libraries instead —
/// that is honest rather than guessing at a quality it cannot see. It should be
/// rare: both backends are asked for media sources on a search.
///
/// Returns null for a single copy: there is nothing to summarise, and the row
/// already names the one library it is in.
String? mediaSearchCopiesLabel(
  List<MediaItem> copies, {
  required String Function(int count) fallbackLabel,
  String separator = ' · ',
}) {
  if (copies.length < 2) return null;

  final resolutions = <String>[];
  for (final copy in copies) {
    final label = _resolutionOf(copy);
    if (label == null) {
      resolutions.clear();
      break;
    }
    resolutions.add(label);
  }

  if (resolutions.isNotEmpty) {
    final counts = <String, int>{};
    for (final label in resolutions) {
      counts[label] = (counts[label] ?? 0) + 1;
    }
    return [
      for (final entry in counts.entries) entry.value == 1 ? entry.key : '${entry.value} × ${entry.key}',
    ].join(separator);
  }

  final libraries = <String>[];
  for (final copy in copies) {
    final title = copy.libraryTitle;
    if (title != null && title.isNotEmpty && !libraries.contains(title)) libraries.add(title);
  }
  if (libraries.length > 1) return libraries.join(separator);

  return fallbackLabel(copies.length);
}

/// The first external id this item names, from the raw row it was mapped
/// from — TMDB, then IMDb, then TVDB.
///
/// Read out of `raw` rather than off a field of its own: the mapper keeps the
/// whole row, the search leg asks for `ProviderIds`, and a new column on
/// [MediaItem] would have to be filled by every caller of every backend to be
/// worth having.
String? _providerId(MediaItem item) {
  final providers = item.raw?['ProviderIds'];
  if (providers is! Map) return null;
  final byName = <String, String>{
    for (final entry in providers.entries)
      if (entry.value case final String value when value.isNotEmpty)
        entry.key.toString().toLowerCase(): value.toLowerCase(),
  };
  for (final source in const ['tmdb', 'imdb', 'tvdb']) {
    if (byName[source] case final id?) return '$source:$id';
  }
  return null;
}

/// The tallest resolution this copy reports, as the label a viewer reads.
String? _resolutionOf(MediaItem item) {
  String? best;
  var bestHeight = 0;
  for (final version in item.mediaVersions ?? const []) {
    final height = version.resolutionHeight;
    if (height == null || height <= bestHeight) continue;
    final raw = version.videoResolution?.trim();
    final label = raw != null && raw.isNotEmpty
        ? resolutionDisplayLabel(raw)
        : switch (resolutionLabelFromDimensions(version.width, version.height)) {
            final derived? => resolutionDisplayLabel(derived),
            null => null,
          };
    if (label == null) continue;
    best = label;
    bestHeight = height;
  }
  return best;
}
