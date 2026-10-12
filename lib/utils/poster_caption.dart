import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';

/// The line under a film's or series' poster title (Plebz): the year, with a
/// film's runtime or a series' number of seasons where the server gave it —
/// "2024 · 166 Min", "2000 · 3 Staffeln", else "2024". Null without a year.
///
/// The runtime is whole minutes rather than the detail page's "2 Std 46 Min":
/// that one fills a poster's width and would be cut at a larger text size. A
/// series gets its seasons, not a runtime — a server knows only an episode's
/// length there, which reads as the whole series' under a poster.
String? posterYearCaption(MediaItem item) {
  final year = item.year;
  if (year == null) return null;
  final extra = switch (item.kind) {
    MediaKind.movie => _minutes(item.durationMs),
    MediaKind.show => _seasons(item.childCount),
    _ => null,
  };
  return extra == null ? '$year' : '$year · $extra';
}

String? _minutes(int? durationMs) {
  if (durationMs == null || durationMs < Duration.millisecondsPerMinute) return null;
  return t.plebz.posterRuntimeMinutes(n: (durationMs / Duration.millisecondsPerMinute).round());
}

String? _seasons(int? count) => count == null || count <= 0 ? null : t.plebz.posterSeasonCount(n: count);
