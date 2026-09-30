import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:string_similarity/string_similarity.dart';
import 'package:unorm_dart/unorm_dart.dart';

import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_person.dart';
import '../media/search_hit.dart';

const int defaultMediaSearchLimit = 100;

final RegExp _searchSeparatorPattern = RegExp(r'[^\p{L}\p{N}\p{M}]+', unicode: true);

List<MediaItem> rankMediaSearchResults(List<MediaItem> items, String query, {int? limit}) =>
    _rankBySearchRelevance(items, query, _mediaScore, _mediaTier, limit: limit);

List<MediaPerson> rankPeopleSearchResults(List<MediaPerson> people, String query, {int? limit}) =>
    _rankBySearchRelevance(people, query, _personScore, (_) => _personTier, limit: limit);

/// Titles and people on one scale; see [_personNameWeight] for how the two
/// compare. Equal scores keep input order, so a caller that lists titles first
/// breaks ties toward titles.
List<SearchHit> rankSearchHits(List<SearchHit> hits, String query, {int? limit}) =>
    _rankBySearchRelevance(hits, query, _hitScore, _hitTier, limit: limit);

List<T> _rankBySearchRelevance<T>(
  List<T> items,
  String query,
  double Function(T item, _NormalizedSearchQuery query) scoreOf,
  int Function(T item) tierOf, {
  int? limit,
}) {
  if (limit != null) {
    RangeError.checkNotNegative(limit, 'limit');
    if (limit == 0) return const [];
  }
  if (items.isEmpty) return const [];

  final searchQuery = _NormalizedSearchQuery(query);
  if (searchQuery.text.isEmpty) {
    return limit == null ? List<T>.of(items) : items.take(limit).toList();
  }

  _Ranked<T> rank(int i) =>
      _Ranked(item: items[i], tier: tierOf(items[i]), score: scoreOf(items[i], searchQuery), originalIndex: i);

  if (limit == null || limit >= items.length) {
    final ranked = [for (var i = 0; i < items.length; i++) rank(i)]..sort(_compareRankedBestFirst);
    return [for (final entry in ranked) entry.item];
  }

  final retained = HeapPriorityQueue<_Ranked<T>>(_compareRankedWorstFirst);
  for (var i = 0; i < items.length; i++) {
    final candidate = rank(i);
    if (retained.length < limit) {
      retained.add(candidate);
      continue;
    }
    if (_compareRankedBestFirst(candidate, retained.first) < 0) {
      retained
        ..removeFirst()
        ..add(candidate);
    }
  }

  final ranked = retained.toList()..sort(_compareRankedBestFirst);
  return [for (final entry in ranked) entry.item];
}

double _hitScore(SearchHit hit, _NormalizedSearchQuery query) => switch (hit) {
  MediaSearchHit(:final item) => _mediaScore(item, query),
  PersonSearchHit(:final person) => _personScore(person, query),
};

int _hitTier(SearchHit hit) => switch (hit) {
  MediaSearchHit(:final item) => _mediaTier(item),
  PersonSearchHit() => _personTier,
};

double _mediaScore(MediaItem item, _NormalizedSearchQuery query) {
  final whole = _titleScore(item, query);
  final year = query.year;
  if (year == null) return whole;

  // A year the viewer typed is usually a *filter*, not four more characters of
  // the name: "Dune 2021" against the title "Dune" was a fuzzy partial, and
  // anything actually called "Dune 2021 Trailer" outscored the film.
  //
  // But sometimes the number really is the name — "Blade Runner 2049", "2001".
  // Both readings are scored and the better one counts. The split reading is
  // held five per cent below, which is more than the year is worth: a title
  // that is exactly what was typed therefore wins against one that had to have
  // the year taken off it first, however well its own year agrees. The bonus
  // is small for a second reason — a release year is the field backends most
  // often disagree on by one, so it may tip a draw and never overturn a
  // better match.
  final split = _titleScore(item, query.titleQuery) * 0.95 + (item.year == year ? 30 : 0);
  return math.max(whole, split);
}

double _titleScore(MediaItem item, _NormalizedSearchQuery query) {
  var best = query.score(item.title, 1.0);
  best = math.max(best, query.score(item.titleSort, 0.98));
  best = math.max(best, query.score(item.originalTitle, 0.96));
  best = math.max(best, query.score(item.grandparentTitle, 0.9));
  best = math.max(best, query.score(item.parentTitle, 0.8));
  return best;
}

/// A person's name scores 95% of a title's. Within one match class (prefix,
/// substring, tokens) the shorter candidate earns the higher closeness bonus,
/// and names are shorter than titles, so at full weight "Rick" ranked every
/// actor named Rick above *Rick and Morty*. At 0.95 a title beats a person in
/// the same class, while an exact name (950) still beats every partial title
/// match (a prefix peaks just under 950), and a name prefix still beats a
/// title that merely contains the query.
const double _personNameWeight = 0.95;

double _personScore(MediaPerson person, _NormalizedSearchQuery query) => query.score(person.name, _personNameWeight);

int _mediaTier(MediaItem item) => _kindTier(item.kind);

/// Which band of the results this kind belongs in. Lower is higher up, and it
/// is decided *before* the score.
///
/// Nobody searches for an episode title. Every sitcom has an episode called
/// "Der Herr der Ringe", and several of them match that query better than the
/// film does — exactly, in fact, while the film has an article in front of it.
/// A bonus cannot fix that: the gap between an exact match and a partial one is
/// a hundred points, and any bonus large enough to bridge it would be large
/// enough to scramble everything else.
///
/// So it is a tier, not a bonus. A thing you set out to find outranks a part of
/// one whatever their names happen to do, and the chip strip above the results
/// is there for the rare time someone did want the episodes — one press, and
/// they are the only thing on screen, ranked among themselves as before.
int _kindTier(MediaKind kind) => switch (kind) {
  // Something you go looking for.
  MediaKind.movie || MediaKind.show || MediaKind.collection => 0,
  // Something you go looking for, one level in.
  MediaKind.season || MediaKind.artist || MediaKind.album || MediaKind.playlist => 1,
  // A part of one of the above.
  MediaKind.episode || MediaKind.track => 2,
  _ => 1,
};

/// A person is something you go looking for, so people share the top band
/// with films and shows and are ordered against them by score alone — which
/// is what [_personNameWeight] is tuned for.
const int _personTier = 0;

/// Leading articles, across the languages a European media library actually
/// holds. Only ever removed from the *front*, and only as a whole word.
///
/// Deliberately not English-only: a list that trimmed "The Boys" and left "Les
/// Boys" and "Los Boys" where they were would rank a title higher for being in
/// English, which is a bias and not a relevance signal. Single ambiguous
/// letters are left out — Italian "I" and Portuguese "O" are also words and
/// whole titles, and the gain does not pay for what they would swallow.
const Set<String> _leadingArticles = {
  'der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einen', 'einem', 'eines', //
  'the', 'a', 'an', //
  'le', 'la', 'les', 'un', 'une', //
  'el', 'los', 'las', 'una', 'unos', 'unas', //
  'il', 'lo', 'gli', 'uno', //
  'os', 'um', 'uma', //
  'het', 'een', //
};

({int? year, String rest}) _splitTrailingYear(String text) {
  final tokens = _tokens(text);
  if (tokens.length < 2) return (year: null, rest: text);
  for (final index in [tokens.length - 1, 0]) {
    final token = tokens[index];
    if (token.length != 4) continue;
    final year = int.tryParse(token);
    if (year == null || year < 1870 || year > 2200) continue;
    final rest = [...tokens]..removeAt(index);
    return (year: year, rest: rest.join(' '));
  }
  return (year: null, rest: text);
}

String _withoutLeadingArticle(String value) {
  final space = value.indexOf(' ');
  if (space <= 0) return value;
  return _leadingArticles.contains(value.substring(0, space)) ? value.substring(space + 1) : value;
}

/// Produces an accent-sensitive search key where canonical/compatibility
/// equivalents and Unicode typography compare alike.
String normalizeSearchText(String? value) {
  if (value == null) return '';
  return nfkc(value).toLowerCase().replaceAll(_searchSeparatorPattern, ' ').trim();
}

double _scoreNormalizedField(_NormalizedSearchQuery query, String candidate) {
  if (candidate == query.text) return 1000;

  if (candidate.startsWith(query.text)) return 900 + _lengthCloseness(query.text, candidate, 50);

  if (candidate.contains(query.text)) return 800 + _lengthCloseness(query.text, candidate, 50);

  final queryTokens = query.tokens;
  final candidateTokens = _tokens(candidate);
  if (queryTokens.isEmpty || candidateTokens.isEmpty) return 0;

  final candidateTokenSet = candidateTokens.toSet();
  final matchingTokens = queryTokens.where(candidateTokenSet.contains).length;
  final sortedCandidate = _sortedTokens(candidateTokens);
  final tokenSimilarity = StringSimilarity.compareTwoStrings(query.sortedTokens, sortedCandidate);
  final rawSimilarity = StringSimilarity.compareTwoStrings(query.text, candidate);
  final fuzzyScore = math.max(rawSimilarity, tokenSimilarity) * 650;

  if (matchingTokens == queryTokens.length) return math.max(700 + tokenSimilarity * 100, fuzzyScore);
  if (matchingTokens > 0) return math.max(400 + (matchingTokens / queryTokens.length) * 100, fuzzyScore);

  return fuzzyScore;
}

List<String> _tokens(String value) => value.split(' ').where((token) => token.isNotEmpty).toList();

String _sortedTokens(List<String> tokens) {
  final sorted = List<String>.of(tokens)..sort();
  return sorted.join(' ');
}

double _lengthCloseness(String query, String candidate, double maxBonus) {
  final longest = math.max(query.length, candidate.length);
  if (longest == 0) return 0;
  final distance = (candidate.length - query.length).abs();
  final closeness = math.max(0.0, math.min(1.0, 1 - distance / longest));
  return maxBonus * closeness;
}

int _compareRankedBestFirst<T>(_Ranked<T> a, _Ranked<T> b) {
  final tierComparison = a.tier.compareTo(b.tier);
  if (tierComparison != 0) return tierComparison;
  final scoreComparison = b.score.compareTo(a.score);
  if (scoreComparison != 0) return scoreComparison;
  return a.originalIndex.compareTo(b.originalIndex);
}

/// The exact reverse, so the head of the bounded queue is always the entry a
/// better candidate should evict.
int _compareRankedWorstFirst<T>(_Ranked<T> a, _Ranked<T> b) => -_compareRankedBestFirst(a, b);

class _NormalizedSearchQuery {
  _NormalizedSearchQuery(String value) : text = normalizeSearchText(value);
  _NormalizedSearchQuery._(this.text);

  final String text;

  /// A four-digit year at either end of the query, and what is left once it is
  /// taken out.
  ///
  /// Only at an end, and only with something else beside it: "2001" on its own
  /// is a film, not a filter, and a number in the middle of a title ("Blade
  /// Runner 2049 Remastered") is part of the name.
  late final ({int? year, String rest}) _yearSplit = _splitTrailingYear(text);
  int? get year => _yearSplit.year;

  /// The query with a year taken out, for matching against titles.
  late final _NormalizedSearchQuery titleQuery = _yearSplit.year == null
      ? this
      : _NormalizedSearchQuery._(_yearSplit.rest);
  late final List<String> tokens = _tokens(text);
  late final String sortedTokens = _sortedTokens(tokens);

  late final String withoutArticle = _withoutLeadingArticle(text);

  /// The same query with a leading article off it, for the second pass in
  /// [score]. Built once per query rather than per candidate.
  late final _NormalizedSearchQuery articleStripped = withoutArticle == text
      ? this
      : _NormalizedSearchQuery._(withoutArticle);

  /// Relevance of [value] to this query on the 0–1000 scale, times [weight].
  double score(String? value, double weight) {
    final candidate = normalizeSearchText(value);
    if (candidate.isEmpty) return 0;
    final direct = _scoreNormalizedField(this, candidate) * weight;

    // Nobody types the article. "herr der ringe" is not an exact match for "Der
    // Herr der Ringe", so the film scored as a *contains* — 800 — while an
    // episode of a sitcom titled exactly "Herr der Ringe" scored 1000 and stood
    // above it. One word nobody thinks of as part of the name decided the whole
    // order.
    //
    // So the same comparison runs again with a leading article off both sides,
    // and the better of the two counts. A hair under full weight, so a title
    // that really is exact still outranks one that had to be trimmed to get
    // there: type "Die Hard" and you get Die Hard, not something called "Hard".
    final trimmed = _withoutLeadingArticle(candidate);
    if (trimmed == candidate && withoutArticle == text) return direct;
    return math.max(direct, _scoreNormalizedField(articleStripped, trimmed) * weight * 0.995);
  }
}

class _Ranked<T> {
  const _Ranked({required this.item, required this.tier, required this.score, required this.originalIndex});

  final T item;
  final int tier;
  final double score;
  final int originalIndex;
}
