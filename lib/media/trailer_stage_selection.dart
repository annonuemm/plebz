import 'library_query.dart';
import 'media_filter.dart';
import 'media_kind.dart';
import 'year_filter.dart';

/// What the viewer is in the mood for: films, series, or no preference.
enum TrailerStageKind {
  any,
  movie,
  show;

  /// The library kinds this draws from. `any` takes both, which is why the
  /// stage asks each library separately rather than building one query.
  List<MediaKind> get mediaKinds => switch (this) {
    TrailerStageKind.any => const [MediaKind.movie, MediaKind.show],
    TrailerStageKind.movie => const [MediaKind.movie],
    TrailerStageKind.show => const [MediaKind.show],
  };

  bool accepts(MediaKind kind) => mediaKinds.contains(kind);
}

/// One evening's answer to "what am I in the mood for": a kind, any number of
/// genres, and a release-year range.
///
/// Every part may be left open, and an open part is not a special case — it is
/// simply a clause the query never carries. An entirely open selection asks
/// for the whole library in random order, which is a perfectly good evening.
class TrailerStageSelection {
  const TrailerStageSelection({
    this.kind = TrailerStageKind.any,
    this.genres = const <String>{},
    this.years = YearRange.none,
  });

  final TrailerStageKind kind;

  /// Display names, not backend ids: a genre's id is per-library on Plex, so
  /// the name is the only identity that survives two libraries and two
  /// servers. Each library resolves these to its own values at query time —
  /// see [genreValuesFor].
  final Set<String> genres;

  final YearRange years;

  bool get isWideOpen => kind == TrailerStageKind.any && genres.isEmpty && years.isEmpty;

  TrailerStageSelection copyWith({TrailerStageKind? kind, Set<String>? genres, YearRange? years}) =>
      TrailerStageSelection(kind: kind ?? this.kind, genres: genres ?? this.genres, years: years ?? this.years);

  /// One past the current year: a library carries titles announced for next
  /// year, and an upper bound that excluded them would look like a fault.
  static int get _upperBound => DateTime.now().year + 1;

  /// This library's own values for the chosen [genres], dropped where the
  /// library has no such genre.
  ///
  /// A library that knows none of them contributes nothing to the evening,
  /// which is the right answer rather than an error: a documentary library
  /// genuinely has no "Film noir".
  List<String> genreValuesFor(Map<String, String> libraryGenres) => [for (final genre in genres) ?libraryGenres[genre]];

  /// The query for one library.
  ///
  /// [libraryGenres] maps genre display name to that library's own filter
  /// value. Pass an empty map for a library whose genres were never loaded —
  /// the genre clause is then dropped rather than guessed, so the stage shows
  /// too much rather than nothing.
  LibraryQuery queryFor(
    MediaKind libraryKind, {
    required Map<String, String> libraryGenres,
    int offset = 0,
    int limit = 30,
  }) {
    final genreValues = genreValuesFor(libraryGenres);
    return LibraryQuery(
      kind: libraryKind,
      offset: offset,
      limit: limit,
      // Random is the whole point: the same selection on two evenings must not
      // open with the same trailer. Plex and Jellyfin both translate it.
      sort: const LibrarySort(field: 'random', direction: LibrarySortDirection.ascending),
      // Upstream folded the named genre/year parameters into the clause list
      // in 2.21; the field names are the canonical ones both translators
      // switch on.
      filters: [
        if (genreValues.isNotEmpty) LibraryFilter(field: MediaFilterField.genre, values: genreValues),
        if (years.years(upperBound: _upperBound) case final List<int> picked when picked.isNotEmpty)
          LibraryFilter(field: MediaFilterField.year, values: [for (final year in picked) '$year']),
      ],
    );
  }

  /// Whether a library with these genres can serve this selection at all.
  ///
  /// False only when genres were asked for and this library has none of them;
  /// the stage then leaves the library out instead of paging through it.
  bool canBeServedBy(Map<String, String> libraryGenres) => genres.isEmpty || genreValuesFor(libraryGenres).isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is TrailerStageSelection &&
      other.kind == kind &&
      other.years == years &&
      other.genres.length == genres.length &&
      other.genres.containsAll(genres);

  @override
  int get hashCode => Object.hash(kind, years, Object.hashAllUnordered(genres));

  @override
  String toString() => 'TrailerStageSelection(${kind.name}, genres: $genres, years: $years)';
}

/// The selection for this run of the app.
///
/// Deliberately not a stored setting. The stage asks once per app start, which
/// is what "what am I in the mood for today" means — a mood is not a
/// preference, and reading last week's answer back would be wrong more often
/// than right. [reset] is the "choose again" the stage offers.
class TrailerStageSession {
  TrailerStageSession._();

  static TrailerStageSelection? _selection;

  static TrailerStageSelection? get selection => _selection;

  static void remember(TrailerStageSelection selection) => _selection = selection;

  static void reset() => _selection = null;
}
