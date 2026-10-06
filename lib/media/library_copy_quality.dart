import '../utils/media_quality_labels.dart';
import 'media_item.dart';
import 'media_stream.dart';
import 'media_version.dart';

/// How good one library copy of a title is to watch, as far as its file says:
/// the picture, the sound, and for a series how many episodes the copy holds.
///
/// Read off a film's own file, or off one sample episode for a series — a
/// series has no quality of its own, only its episodes do. Compared with
/// [compareLibraryCopyQuality]; the labels are what a row or the button
/// shows ("4K · DV · TrueHD Atmos").
class LibraryCopyQuality {
  const LibraryCopyQuality({
    required this.resolution,
    required this.dynamicRange,
    required this.audio,
    required this.bitrate,
    this.episodes,
    this.labels = const [],
  });

  /// Resolution class: 4320, 2160, 1080, 720, 480, or 0 when unknown. A class,
  /// not the height: a 4K film in scope is 3840×1600, and its height alone
  /// would class it with 1080p.
  final int resolution;

  /// 0 SDR or unknown, 1 HDR10/HLG, 2 HDR10+, 3 Dolby Vision.
  final int dynamicRange;

  /// 0 none or unknown, 1 stereo or less, 2 lossy surround — AC3, E-AC-3,
  /// DTS core alike —, 3 lossless or DTS-HD, 4 Atmos.
  ///
  /// Classes, not codecs: E-AC-3 5.1 and AC3 5.1 are the same thing to the
  /// ear, and ranking one above the other once put a 7 Mbit/s copy ahead of
  /// a 26 Mbit/s one of the same episode before the bitrate was ever asked.
  final int audio;

  /// kbit/s, 0 when unknown.
  final int bitrate;

  /// Episodes in the copy — series only.
  final int? episodes;

  final List<String> labels;

  /// [item]'s best version: a film's own file, or a series' sample episode.
  ///
  /// [dolbyVisionDisabled] follows the switch in the playback settings: with
  /// Dolby Vision off a profile 8 file plays its HDR10 base layer, so it is
  /// worth what an HDR10 file is. Profile 5 has no base layer and stays Dolby
  /// Vision either way.
  factory LibraryCopyQuality.of(MediaItem item, {int? episodes, bool dolbyVisionDisabled = false}) {
    final versions = item.mediaVersions ?? const <MediaVersion>[];
    LibraryCopyQuality? best;
    for (var i = 0; i < versions.length; i++) {
      final candidate = _ofVersion(item, versions[i], i, episodes, dolbyVisionDisabled);
      if (best == null || _comparePicture(candidate, best) < 0) best = candidate;
    }
    return best ?? LibraryCopyQuality(resolution: 0, dynamicRange: 0, audio: 0, bitrate: 0, episodes: episodes);
  }

  static LibraryCopyQuality _ofVersion(
    MediaItem item,
    MediaVersion version,
    int index,
    int? episodes,
    bool dolbyVisionDisabled,
  ) {
    final video = _firstStream(version, MediaStreamKind.video);
    return LibraryCopyQuality(
      resolution: _resolutionClass(version),
      dynamicRange: _dynamicRangeRank(video, dolbyVisionDisabled: dolbyVisionDisabled),
      audio: _audioRank(_playedAudio(version)),
      bitrate: version.bitrate ?? 0,
      episodes: episodes,
      labels: [
        ...buildMediaVideoLabels(
          item,
          versionIndex: index,
          includeBitrate: false,
          dolbyVisionDisabled: dolbyVisionDisabled,
        ),
        ?buildMediaAudioLabel(item, versionIndex: index),
      ],
    );
  }

  /// Whether anything at all is known about the file.
  bool get isKnown => resolution > 0 || dynamicRange > 0 || audio > 0 || bitrate > 0;
}

/// Which library copy the Explore detail page puts first and opens from the
/// button beside the poster — the viewer's choice in the playback settings.
enum BestCopyPreference {
  /// Picture, then sound, then bitrate; episodes only on a tie.
  best,

  /// For a series, the copy with the most episodes; the best of those. A film
  /// has no episodes, so it ranks as with [best].
  complete,

  /// Copies up to 1080p first, the best of those; 4K only where nothing
  /// smaller exists.
  fullHd,
}

/// Best first, as [preference] has it — by default picture (resolution, then
/// dynamic range), then sound, then bitrate, and only when all of that is
/// equal, the copy with more episodes. The viewer's call: a copy in 4K that
/// lacks episodes still comes before a complete one in HD, and says so.
/// Unknown comes last whatever the preference.
int compareLibraryCopyQuality(
  LibraryCopyQuality? a,
  LibraryCopyQuality? b, {
  BestCopyPreference preference = BestCopyPreference.best,
}) {
  final aKnown = a != null && a.isKnown;
  final bKnown = b != null && b.isKnown;
  if (aKnown != bKnown) return aKnown ? -1 : 1;
  if (!aKnown || !bKnown) return 0;
  final byEpisodes = (b.episodes ?? 0).compareTo(a.episodes ?? 0);
  if (preference == BestCopyPreference.complete && byEpisodes != 0) return byEpisodes;
  if (preference == BestCopyPreference.fullHd) {
    final byFit = _aboveFullHd(a).compareTo(_aboveFullHd(b));
    if (byFit != 0) return byFit;
  }
  final byPicture = _comparePicture(a, b);
  if (byPicture != 0) return byPicture;
  return byEpisodes;
}

/// 1 for a copy above 1080p, 0 for one up to it — or of unknown size.
int _aboveFullHd(LibraryCopyQuality quality) => quality.resolution > 1080 ? 1 : 0;

int _comparePicture(LibraryCopyQuality a, LibraryCopyQuality b) {
  for (final (x, y) in [
    (a.resolution, b.resolution),
    (a.dynamicRange, b.dynamicRange),
    (a.audio, b.audio),
    (a.bitrate, b.bitrate),
  ]) {
    if (x != y) return y.compareTo(x);
  }
  return 0;
}

int _classOfHeight(int height) => switch (height) {
  >= 4000 => 4320,
  >= 2000 => 2160,
  >= 1000 => 1080,
  >= 700 => 720,
  > 0 => 480,
  _ => 0,
};

int _classOfWidth(int width) => switch (width) {
  >= 7000 => 4320,
  >= 3500 => 2160,
  >= 1800 => 1080,
  >= 1200 => 720,
  > 0 => 480,
  _ => 0,
};

int _resolutionClass(MediaVersion version) {
  final byHeight = _classOfHeight(version.resolutionHeight ?? 0);
  final byWidth = _classOfWidth(version.width ?? 0);
  return byHeight > byWidth ? byHeight : byWidth;
}

int _dynamicRangeRank(MediaStream? video, {required bool dolbyVisionDisabled}) {
  if (video == null) return 0;
  if (video.dolbyVision && !(dolbyVisionDisabled && video.dolbyVisionProfile != 5)) return 3;
  if (video.hdr10Plus) return 2;
  if (video.hdr || video.dolbyVision) return 1;
  return 0;
}

/// The sound as it will play: the track the file marks selected or default,
/// the way the detail page's label reads it — a German AC3 beside an English
/// Atmos track plays the German one.
MediaStream? _playedAudio(MediaVersion version) {
  MediaStream? first;
  MediaStream? containerDefault;
  for (final part in version.parts) {
    for (final stream in part.streams) {
      if (stream.kind != MediaStreamKind.audio) continue;
      first ??= stream;
      if (stream.selected) return stream;
      if (stream.isDefault) containerDefault ??= stream;
    }
  }
  return containerDefault ?? first;
}

int _audioRank(MediaStream? stream) {
  if (stream == null) return 0;
  final named = [stream.codec, stream.profile, stream.title, stream.displayTitle];
  if (named.whereType<String>().any((value) => value.toLowerCase().contains('atmos'))) return 4;
  final codec = (stream.codec ?? '').toLowerCase();
  final profile = (stream.profile ?? '').toLowerCase();
  if (codec == 'truehd' || codec == 'mlp' || codec == 'flac' || codec.startsWith('pcm')) return 3;
  // DTS-HD MA, DTS-HD HRA and DTS:X arrive as codec `dts`; the profile names
  // them (see the audio codec naming note in the detail labels).
  if (codec.startsWith('dts') && (profile.contains('hd') || profile.contains(':x') || profile.contains('dts-x'))) {
    return 3;
  }
  final channels = stream.channels;
  if (channels != null && channels <= 2) return 1;
  return 2;
}

MediaStream? _firstStream(MediaVersion version, MediaStreamKind kind) {
  for (final part in version.parts) {
    for (final stream in part.streams) {
      if (stream.kind == kind) return stream;
    }
  }
  return null;
}
