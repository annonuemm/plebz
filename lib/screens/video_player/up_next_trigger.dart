/// When the "up next" panel is due, and when it is not.
///
/// Two ways in, because the servers only sometimes know where the credits
/// start: the marker when there is one, and otherwise a share of the runtime.
/// Kept as a function so the rule can be read and checked without a player.
library;

import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';

/// Share of the runtime after which the panel appears when no credits marker
/// says otherwise. Late enough that it does not sit over the last scene,
/// early enough to be an offer rather than an announcement.
const upNextFallbackFraction = 0.97;

/// Below this there is no "end" worth announcing — a five-minute extra would
/// otherwise put the panel up almost as soon as it started.
const upNextMinimumRuntime = Duration(minutes: 5);

bool shouldShowUpNext({
  required Duration position,
  required Duration duration,
  required bool hasNextEpisode,
  required bool dismissed,
  bool enabled = true,
  Duration? creditsStart,
}) {
  if (!enabled || !hasNextEpisode || dismissed) return false;
  if (duration <= upNextMinimumRuntime) return false;
  if (position <= Duration.zero) return false;

  // A marker is a statement about this episode; the fraction is a guess about
  // episodes in general, so the marker wins wherever there is one.
  if (creditsStart != null) return position >= creditsStart;
  return position.inMilliseconds >= duration.inMilliseconds * upNextFallbackFraction;
}

/// Share of the runtime after which the end card opens on its own when no
/// credits marker says where they begin (Plebz, the user's call 2026-10-14:
/// 97 % is often still the story in a series).
const endCardFraction = 0.98;

/// When the end card opens on its own: at the credits marker, or else at
/// [endCardFraction] of the runtime.
bool shouldOpenEndCard({required Duration position, required Duration duration, Duration? creditsStart}) {
  if (duration <= upNextMinimumRuntime || position <= Duration.zero) return false;
  if (creditsStart != null) return position >= creditsStart;
  return position.inMilliseconds >= duration.inMilliseconds * endCardFraction;
}

/// Whether Back opens the end card rather than leaving the player: from
/// [percent] of the runtime on.
bool endCardBackOpens({required Duration position, required Duration duration, required int percent}) {
  if (duration <= upNextMinimumRuntime || position <= Duration.zero) return false;
  return position.inMilliseconds >= duration.inMilliseconds * percent / 100;
}

/// The title the end card suggests when nothing follows (Plebz, the user's
/// call 2026-10-14): from the server's "more like this" rows, one of [kind]
/// that is not in [exclude], unwatched before watched, the similar-titles row
/// before rows of the same director or cast. Null when there is none.
MediaItem? pickEndCardSuggestion(List<MediaHub> hubs, {required MediaKind kind, Set<String> exclude = const {}}) {
  bool similar(MediaHub hub) => (hub.identifier ?? hub.id).toLowerCase().contains('similar');
  final ordered = [...hubs.where(similar), ...hubs.where((hub) => !similar(hub))];
  final candidates = [
    for (final hub in ordered)
      for (final item in hub.items)
        if (item.kind == kind && !exclude.contains(item.id)) item,
  ];
  for (final item in candidates) {
    if (!item.isWatched) return item;
  }
  return candidates.firstOrNull;
}
