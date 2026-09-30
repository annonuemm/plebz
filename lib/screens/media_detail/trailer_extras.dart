/// Which of an item's extras is its trailer.
///
/// The detail page's Trailer button plays what this picks; a server that names
/// a primary trailer gets its choice honoured, because that is the one its own
/// apps play.
library;

import '../../media/media_item.dart';

/// Whether [extra] is a trailer rather than one of the other extras — a
/// featurette, a deleted scene, a behind-the-scenes reel.
///
/// Plex says so in the item's `subtype`, Jellyfin in `ExtraType`; a Jellyfin
/// item fetched on its own says it in `Type` instead.
bool isTrailerExtra(MediaItem extra) {
  if (extra case PlexMediaItem(:final subtype?)) {
    return subtype.toLowerCase() == 'trailer';
  }
  final raw = extra.raw;
  final extraType = raw?['ExtraType'] as String?;
  final type = raw?['Type'] as String?;
  return extraType?.toLowerCase() == 'trailer' || type?.toLowerCase() == 'trailer';
}

/// The trailer for [item], or null when the extras hold none.
///
/// A server that names a primary trailer gets its choice honoured — Plex's
/// `primaryExtraKey` is the one its own apps play — and anything else falls
/// back to the first trailer among the extras.
MediaItem? primaryTrailerFor(MediaItem item, List<MediaItem>? extras) {
  if (extras == null || extras.isEmpty) return null;

  if (item case PlexMediaItem(:final trailerKey?)) {
    final primaryKey = trailerKey.split('/').last;
    for (final extra in extras) {
      if (extra.id == primaryKey) return extra;
    }
  }

  for (final extra in extras) {
    if (isTrailerExtra(extra)) return extra;
  }
  return null;
}
