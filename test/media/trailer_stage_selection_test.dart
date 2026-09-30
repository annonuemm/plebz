import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_filter.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/trailer_stage_selection.dart';
import 'package:plezy/media/year_filter.dart';
import 'package:plezy/services/library_query_translator.dart';

void main() {
  group('TrailerStageSelection', () {
    const libraryGenres = {'Action': '1', 'Drama': '2'};

    test('an open selection carries no clause at all', () {
      const selection = TrailerStageSelection();
      final query = selection.queryFor(MediaKind.movie, libraryGenres: libraryGenres);

      expect(selection.isWideOpen, isTrue);
      expect(_clause(query, MediaFilterField.genre), isNull);
      expect(_clause(query, MediaFilterField.year), isNull);
      expect(query.kind, MediaKind.movie);
      // "Anything" must reach the wire as an absent filter, not as an empty
      // one — an empty `genre=` would filter everything away.
      final wire = const PlexLibraryQueryTranslator().toQueryParameters(query);
      expect(wire.containsKey('genre'), isFalse);
      expect(wire.containsKey('year'), isFalse);
      expect(wire['sort'], 'random:asc');
    });

    test('genres are resolved to the library\'s own values', () {
      const selection = TrailerStageSelection(genres: {'Drama'});
      final query = selection.queryFor(MediaKind.movie, libraryGenres: libraryGenres);

      expect(_clause(query, MediaFilterField.genre), ['2']);
    });

    test('a genre this library does not know is dropped, not guessed', () {
      const selection = TrailerStageSelection(genres: {'Drama', 'Film noir'});

      expect(selection.genreValuesFor(libraryGenres), ['2']);
    });

    test('a library that knows none of the chosen genres cannot serve them', () {
      const selection = TrailerStageSelection(genres: {'Film noir'});

      expect(selection.canBeServedBy(libraryGenres), isFalse);
      expect(const TrailerStageSelection().canBeServedBy(const {}), isTrue);
    });

    test('a library whose genres were never loaded still gets served', () {
      // An empty catalog means "unknown here", so the clause is dropped and
      // the stage shows too much rather than nothing.
      const selection = TrailerStageSelection(genres: {'Drama'});
      final query = selection.queryFor(MediaKind.movie, libraryGenres: const {});

      expect(_clause(query, MediaFilterField.genre), isNull);
    });

    test('a year range is written out, because that is the only form the servers take', () {
      const selection = TrailerStageSelection(years: YearRange(from: 1990, to: 1993));
      final query = selection.queryFor(MediaKind.movie, libraryGenres: libraryGenres);

      expect(_clause(query, MediaFilterField.year), ['1990', '1991', '1992', '1993']);
    });

    test('an open end runs to next year', () {
      const selection = TrailerStageSelection(years: YearRange(from: 1990));
      final query = selection.queryFor(MediaKind.movie, libraryGenres: libraryGenres);

      expect(_clause(query, MediaFilterField.year)!.first, '1990');
      expect(_clause(query, MediaFilterField.year)!.last, '${DateTime.now().year + 1}');
    });

    test('the kind decides which libraries are asked', () {
      expect(TrailerStageKind.any.accepts(MediaKind.movie), isTrue);
      expect(TrailerStageKind.any.accepts(MediaKind.show), isTrue);
      expect(TrailerStageKind.movie.accepts(MediaKind.show), isFalse);
      expect(TrailerStageKind.show.accepts(MediaKind.movie), isFalse);
    });
  });

  group('TrailerStageSession', () {
    setUp(TrailerStageSession.reset);

    test('holds this run\'s answer and forgets it on reset', () {
      expect(TrailerStageSession.selection, isNull);

      TrailerStageSession.remember(const TrailerStageSelection(kind: TrailerStageKind.movie));
      expect(TrailerStageSession.selection?.kind, TrailerStageKind.movie);

      TrailerStageSession.reset();
      expect(TrailerStageSession.selection, isNull);
    });
  });
}

/// The values of the one clause on [field], or null when the query carries
/// none. Upstream folded the named `genres`/`years` parameters into the clause
/// list in 2.21; these tests ask the same questions of the new shape.
List<String>? _clause(LibraryQuery query, String field) {
  for (final clause in query.filters) {
    if (clause.field == field) return clause.values;
  }
  return null;
}
