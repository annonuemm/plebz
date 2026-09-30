import 'package:clock/clock.dart';

import '../../media/library_copy_quality.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';

/// Asks a copy's own server what the copy is worth watching in.
///
/// The copies an external-id lookup finds carry at most a resolution, and a
/// series carries none: its files are its episodes. So a film's detail is
/// fetched for its streams, and for a series its first episode is — one
/// request for the episode, one for its streams, and one more for the episode
/// count only where the lookup did not bring it. Plex and Jellyfin answer
/// through the same client calls, so both are measured the same way.
///
/// Answers are kept for a quarter of an hour per copy: opening a title again,
/// or the next title of the same library, does not ask again.
class LibraryCopyQualityLoader {
  LibraryCopyQualityLoader({required this.clientFor, this.dolbyVisionDisabled = false});

  final MediaServerClient? Function(MediaItem copy) clientFor;
  final bool dolbyVisionDisabled;

  static const _ttl = Duration(minutes: 15);
  static final Map<String, ({LibraryCopyQuality quality, DateTime at})> _kept = {};

  /// Null when the server could not say: unreachable, or a copy without files.
  Future<LibraryCopyQuality?> load(MediaItem copy) async {
    final key = '${copy.globalKey}|$dolbyVisionDisabled';
    final kept = _kept[key];
    if (kept != null && clock.now().difference(kept.at) < _ttl) return kept.quality;

    final client = clientFor(copy);
    if (client == null) return null;
    try {
      final quality = copy.kind == MediaKind.show ? await _ofSeries(client, copy) : await _ofFilm(client, copy);
      if (quality != null) _kept[key] = (quality: quality, at: clock.now());
      return quality;
    } catch (error) {
      appLogger.d('Library copy quality: ${copy.globalKey} could not be read', error: error);
      return null;
    }
  }

  Future<LibraryCopyQuality?> _ofFilm(MediaServerClient client, MediaItem copy) async {
    final detail = await client.fetchItem(copy.id) ?? copy;
    final quality = LibraryCopyQuality.of(detail, dolbyVisionDisabled: dolbyVisionDisabled);
    return quality.isKnown ? quality : null;
  }

  Future<LibraryCopyQuality?> _ofSeries(MediaServerClient client, MediaItem copy) async {
    final page = await client.fetchPlayableDescendantsPage(copy.id, start: 0, size: 1);
    final sample = page.items.firstOrNull;
    if (sample == null) return null;
    final episode = await client.fetchItem(sample.id) ?? sample;
    // The page's total is not trusted for the count: a backend that omits it
    // answers with a "there is more" sentinel, which would read as 2.
    final episodes = copy.leafWatchTotal ?? (await client.fetchItem(copy.id))?.leafWatchTotal;
    final quality = LibraryCopyQuality.of(episode, episodes: episodes, dolbyVisionDisabled: dolbyVisionDisabled);
    return quality.isKnown ? quality : null;
  }

  /// For tests: forget every kept answer.
  static void clearForTesting() => _kept.clear();
}
