import 'media_item.dart';
import 'media_kind.dart';

/// Which kind of title the Watchlist tab shows.
enum WatchlistTypeFilter { all, movies, shows }

/// Which watch state the Watchlist tab shows.
enum WatchlistStatusFilter { any, unwatched, watched }

/// The Watchlist tab's narrowing: a kind and a watch state, and the predicate
/// the two add up to.
///
/// Held as one object so the screen has a single thing to store, persist and
/// hand to the grid, and so the rule itself can be tested without a widget.
class WatchlistFilter {
  const WatchlistFilter({this.type = WatchlistTypeFilter.all, this.status = WatchlistStatusFilter.any});

  final WatchlistTypeFilter type;
  final WatchlistStatusFilter status;

  static const WatchlistFilter none = WatchlistFilter();

  /// Whether this narrows anything. An empty filter is passed to the grid as
  /// no filter at all, so nothing is walked for a list nobody narrowed.
  bool get isEmpty => type == WatchlistTypeFilter.all && status == WatchlistStatusFilter.any;

  WatchlistFilter withType(WatchlistTypeFilter type) => WatchlistFilter(type: type, status: status);

  WatchlistFilter withStatus(WatchlistStatusFilter status) => WatchlistFilter(type: type, status: status);

  /// Whether [item] survives both halves.
  ///
  /// "Not watched" is [MediaItem.isUnwatchedOrInProgress] — the predicate every
  /// other unwatched-only selection in the app already uses — so a series half
  /// seen counts as unfinished here too, and the two answers stay exact
  /// opposites of each other.
  ///
  /// A provider that reports no play state at all leaves its titles unwatched
  /// (Trakt, MAL and AniList never answer; Plex does). That is the honest
  /// reading for a watchlist, and "Watched" then simply finds nothing rather
  /// than inventing an answer.
  bool matches(MediaItem item) {
    final kindMatches = switch (type) {
      WatchlistTypeFilter.all => true,
      WatchlistTypeFilter.movies => item.kind == MediaKind.movie,
      WatchlistTypeFilter.shows => item.kind == MediaKind.show,
    };
    if (!kindMatches) return false;
    return switch (status) {
      WatchlistStatusFilter.any => true,
      WatchlistStatusFilter.unwatched => item.isUnwatchedOrInProgress,
      WatchlistStatusFilter.watched => !item.isUnwatchedOrInProgress,
    };
  }

  @override
  bool operator ==(Object other) => other is WatchlistFilter && other.type == type && other.status == status;

  @override
  int get hashCode => Object.hash(type, status);
}
