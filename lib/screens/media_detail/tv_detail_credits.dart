/// What the TV detail page prints in the corner opposite the summary.
///
/// Kept away from the widget because the interesting part is the choosing, not
/// the drawing: which fields are worth a line, how many names fit before the
/// corner stops being a glance, and what to do when a title only knows half of
/// it.
library;

/// One line of the corner: what it is, and who.
typedef TvDetailCredit = ({String label, String value});

/// The corner's lines, in reading order: direction, studio, cast.
///
/// A field with nothing to say is left out entirely rather than printed empty,
/// so a title that only knows its studio gets one line instead of three
/// — which is also why the corner can come back empty and not be drawn at all.
///
/// [maxDirectors] and [maxCast] are the point where a corner stops being read
/// at a glance. Names beyond them are dropped silently: the full list is a
/// screen of its own, and the cast rail below already carries it.
List<TvDetailCredit> tvDetailCredits({
  required String directorLabel,
  required String directorsLabel,
  required String studioLabel,
  required String castLabel,
  List<String>? directors,
  String? studio,
  List<String>? cast,
  int maxDirectors = 2,
  int maxCast = 3,
}) {
  final credits = <TvDetailCredit>[];

  final directorNames = _names(directors, maxDirectors);
  if (directorNames.isNotEmpty) {
    credits.add((label: directorNames.length > 1 ? directorsLabel : directorLabel, value: directorNames.join(', ')));
  }

  final studioName = studio?.trim();
  if (studioName != null && studioName.isNotEmpty) {
    credits.add((label: studioLabel, value: studioName));
  }

  final castNames = _names(cast, maxCast);
  if (castNames.isNotEmpty) {
    credits.add((label: castLabel, value: castNames.join(', ')));
  }

  return credits;
}

/// The first [limit] usable names: trimmed, blanks dropped, and no one named
/// twice — both backends can list the same person under two credits.
List<String> _names(List<String>? raw, int limit) {
  if (raw == null || limit <= 0) return const [];

  final seen = <String>{};
  final names = <String>[];
  for (final entry in raw) {
    final name = entry.trim();
    if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
    names.add(name);
    if (names.length == limit) break;
  }
  return names;
}
