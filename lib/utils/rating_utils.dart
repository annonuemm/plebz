/// Resolves the brand badge and written label shown beside a score, keyed by
/// the attributed source name every backend mapper normalizes to.
library;

import '../i18n/strings.g.dart';
import '../media/media_rating.dart';

/// Source key of the synthetic score [averagedRatings] produces. Deliberately
/// not a backend key: it carries no brand badge, so it renders with the
/// neutral star and the 0-10 formatting every unbranded score uses.
const String averageRatingSource = 'average';

/// Collapse several attributed scores into their mean, or return [ratings]
/// unchanged when there is nothing to collapse.
///
/// Every backend mapper normalizes `value` to 0-10 before it gets here — the
/// percentage sources are rendered back as `value * 10`% at display time, not
/// stored that way — so the scores are already on one scale and the mean is
/// over comparable numbers.
///
/// Votes are dropped rather than summed: a mean of four scores is not backed
/// by the sum of their voter counts, and claiming so would overstate it.
List<MediaRatingSource> averagedRatings(List<MediaRatingSource> ratings) {
  if (ratings.length < 2) return ratings;
  final sum = ratings.fold<double>(0, (total, rating) => total + rating.value);
  return [MediaRatingSource(source: averageRatingSource, value: sum / ratings.length)];
}

class RatingInfo {
  final String assetPath;
  final String formattedValue;

  /// Width over height of the badge SVG's viewBox. Badges draw at a fixed
  /// height, so this pins the icon's laid-out width, letting metadata lines
  /// measure a badge exactly before building it (#1893).
  final double iconAspect;

  const RatingInfo(this.assetPath, this.formattedValue, this.iconAspect);
}

/// The brand badge for an attributed source key.
///
/// Rotten Tomatoes picks fresh/rotten and upright/spilled by the 60% threshold
/// the tomatometer itself uses — the same state Plex encodes in
/// `image.rating.ripe` / `.rotten` and Jellyfin's own web client applies to
/// `CriticRating`.
///
/// Returns null for keys with no brand badge (`critic`, `audience`, `simkl`,
/// `mal`, `anilist`, `trakt`); those stay labelled with their source name.
RatingInfo? ratingInfoForSource(String source, double value) => switch (source) {
  'imdb' => RatingInfo(_imdbAsset, value.toStringAsFixed(1), _imdbAspect),
  'tmdb' => RatingInfo(_tmdbAsset, _percent(value), _tmdbAspect),
  'rottenTomatoes' || 'rottenTomatoesCritic' =>
    value >= _rottenTomatoesFresh
        ? RatingInfo(_rtFreshAsset, _percent(value), _rtFreshAspect)
        : RatingInfo(_rtRottenAsset, _percent(value), _rtRottenAspect),
  'rottenTomatoesAudience' =>
    value >= _rottenTomatoesFresh
        ? RatingInfo(_rtUprightAsset, _percent(value), _rtUprightAspect)
        : RatingInfo(_rtSpilledAsset, _percent(value), _rtSpilledAspect),
  _ => null,
};

/// Localized name for an attributed source key, or null when the key is
/// unknown and the score should be dropped rather than labelled raw.
String? ratingSourceLabel(String source) => switch (source) {
  averageRatingSource => t.common.ratingSource.average,
  'critic' => t.common.ratingSource.critic,
  'audience' => t.common.ratingSource.audience,
  'imdb' => t.common.ratingSource.imdb,
  'tmdb' => t.common.ratingSource.tmdb,
  'rottenTomatoes' => t.common.ratingSource.rottenTomatoes,
  // Plex splits Rotten Tomatoes into its two panels, so both the provenance
  // and the critic/audience distinction survive.
  'rottenTomatoesCritic' => t.common.ratingSource.rottenTomatoesCritic,
  'rottenTomatoesAudience' => t.common.ratingSource.rottenTomatoesAudience,
  'simkl' => t.common.ratingSource.simkl,
  'mal' => t.common.ratingSource.mal,
  'anilist' => t.common.ratingSource.anilist,
  'trakt' => t.common.ratingSource.trakt,
  _ => null,
};

const String _imdbAsset = 'assets/rating_icons/imdb.svg';
const String _tmdbAsset = 'assets/rating_icons/tmdb.svg';
const String _rtFreshAsset = 'assets/rating_icons/rt_fresh.svg';
const String _rtRottenAsset = 'assets/rating_icons/rt_rotten.svg';
const String _rtUprightAsset = 'assets/rating_icons/rt_upright.svg';
const String _rtSpilledAsset = 'assets/rating_icons/rt_spilled.svg';

// Each aspect is its svg's viewBox width over height;
// `test/widgets/fitted_metadata_line_test.dart` checks them against the
// rendered assets so they can't drift silently.
const double _imdbAspect = 575 / 289.83;
const double _tmdbAspect = 185.04 / 133.4;
const double _rtFreshAspect = 138.75 / 141.25;
const double _rtRottenAspect = 145 / 140;
const double _rtUprightAspect = 106.25 / 140;
const double _rtSpilledAspect = 143.75 / 108.75;

/// Ratings are normalized to a 0-10 scale; Rotten Tomatoes is a percentage.
const double _rottenTomatoesFresh = 6.0;

String _percent(double value) => '${(value * 10).toStringAsFixed(0)}%';
