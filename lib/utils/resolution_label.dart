/// How far below a tier's nominal dimension a file may sit and still count as
/// that tier.
///
/// Real releases rarely match the nominal frame exactly: a 4K scope master
/// lands at 3828x1596 rather than 3840x1600 once the mastering crop is
/// applied, and a 1080p scope file at 1912x796. An exact `>= 3840` test drops
/// every one of those a full tier — which is what made a 4K file Jellyfin
/// labels "4K" show up as "1080p", and, because the label is part of
/// [MediaVersion.signature], made version matching miss between two episodes
/// cropped differently.
///
/// 5% is wide enough for mastering crops and narrow enough that the next tier
/// down cannot reach into it: 1080p's nominal 1920 is far below 4K's 3648
/// cutoff, and 720p's 1280 far below 1080p's 1824.
const double _tierTolerance = 0.95;

bool _reaches(int? value, int nominal) => value != null && value >= nominal * _tierTolerance;

/// Map video dimensions onto the canonical resolution label the rest of the
/// app uses (`'4k'`, `'1080'`, `'720'`, `'480'`, or the raw height for sizes
/// below the lowest tier). Returns `null` when both dimensions are null.
///
/// Width is decisive for scope-cropped files, whose height falls far short of
/// the tier while the width barely moves: 3828x1596 is a 4K file, not a
/// 1080p one.
///
/// Plex hands the label back already in its `Media.videoResolution` field;
/// Jellyfin only gives raw pixel dimensions, so the Jellyfin mapper and
/// playback path both call this to produce the same shape.
String? resolutionLabelFromDimensions(int? width, int? height) {
  if (_reaches(width, 3840) || _reaches(height, 2160)) return '4k';
  if (_reaches(width, 1920) || _reaches(height, 1080)) return '1080';
  if (_reaches(width, 1280) || _reaches(height, 720)) return '720';
  if (_reaches(width, 854) || _reaches(height, 480)) return '480';
  return height?.toString();
}

/// Height-only overload, for callers that never learn the width. Scope files
/// cannot be told from their tier by height alone, so prefer
/// [resolutionLabelFromDimensions] wherever the width is known.
String? resolutionLabelFromHeight(int? height) => resolutionLabelFromDimensions(null, height);

final _numericResolutionValue = RegExp(r'^(\d+)(?:p)?$');

/// Format a canonical resolution label — or a raw numeric height, with or
/// without a trailing `p` — for display: `'1080'`/`'1080p'` → `'1080p'`,
/// `'4k'`/`'uhd'`/heights ≥ 2160 → `'4K'`, `'sd'` → `'SD'`; anything else is
/// uppercased verbatim.
String resolutionDisplayLabel(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == '4k' || normalized == 'uhd') return '4K';
  if (normalized == 'sd') return 'SD';

  final numeric = _numericResolutionValue.firstMatch(normalized);
  if (numeric != null) {
    final height = int.tryParse(numeric.group(1)!);
    if (height != null && height >= 2160) return '4K';
    return '${numeric.group(1)}p';
  }

  return value.trim().toUpperCase();
}
