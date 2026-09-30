import '../i18n/strings.g.dart';
import '../models/catalog/catalog_metadata.dart';
import 'formatters.dart';

/// The poster label for a show's next episode — one unit, never a breakdown.
///
/// Returns null once the episode's day has passed, which is the signal not to
/// draw anything.
///
/// Counted in **calendar days**, not in elapsed time. Most providers date an
/// episode without a time: TMDB's `airDate` and Plex's
/// `nextEpisodeOriginallyAvailableAt` are days, and parsing either lands on
/// local midnight. Measured as a duration, an episode airing tomorrow would
/// read "in 7Std" at five in the afternoon — true of the clock, wrong about
/// the thing being asked. A viewer means sleeps, so days are what is counted.
///
/// A source that does carry a time of day (AniList's `airingAt` is a real
/// timestamp) gets the clock back for today's episode, where the hour is
/// exactly what is worth knowing.
String? catalogNextAiringLabel(CatalogNextEpisode next, DateTime now, {required bool is24Hour}) {
  final airsAt = next.airsAt.toLocal();
  final days = _calendarDaysBetween(now, airsAt);
  if (days < 0) return null;

  if (days == 0) {
    // Midnight means the provider gave a date and no time; announcing "at
    // 00:00" would dress up a missing value as a broadcast slot.
    final hasTimeOfDay = airsAt.hour != 0 || airsAt.minute != 0;
    return hasTimeOfDay
        ? t.explore.badge.nextAiringAt(time: formatClockTime(airsAt, is24Hour: is24Hour))
        : t.explore.badge.nextAiringToday;
  }

  return t.explore.badge.nextAiringIn(duration: _largestUnit(Duration(days: days)));
}

/// Whole days from [from]'s date to [to]'s date, ignoring the clock.
int _calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime(to.year, to.month, to.day).difference(DateTime(from.year, from.month, from.day)).inDays;

/// The coarsest unit of [duration] on its own: "15W" out of "15W 6T".
///
/// Takes the first token of the localized breakdown rather than assembling
/// unit names here, so every locale keeps the wording it already had.
String _largestUnit(Duration duration) {
  final full = formatDurationTextual(duration.inMilliseconds);
  final first = full.split(' ').firstWhere((part) => part.isNotEmpty, orElse: () => '');
  return first.isEmpty ? full : first;
}
