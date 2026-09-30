/// When the "up next" panel is due, and when it is not.
///
/// Two ways in, because the servers only sometimes know where the credits
/// start: the marker when there is one, and otherwise a share of the runtime.
/// Kept as a function so the rule can be read and checked without a player.
library;

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
