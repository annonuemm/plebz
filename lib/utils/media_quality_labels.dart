import '../media/media_item.dart';
import '../media/media_source_info.dart';
import '../media/media_stream.dart';
import '../media/media_version.dart';
import 'codec_utils.dart';
import 'resolution_label.dart';
import 'formatters.dart';

/// The picture, then the sound: [buildMediaVideoLabels] plus the format of the
/// version's own audio stream.
///
/// For a line that names a *chosen* audio track separately, use
/// [buildMediaVideoLabels] and take the format from that track's own label —
/// the stream picked here is the container's, which is not always the one the
/// player's selection ladder lands on.
List<String> buildMediaQualityLabels(MediaItem item, {int versionIndex = 0, bool dolbyVisionDisabled = false}) {
  final version = _selectedVersion(item.mediaVersions, versionIndex);
  if (version == null) return const [];

  final audioLabel = _formatAudio(_selectedAudioStream(version));
  return [
    ...buildMediaVideoLabels(item, versionIndex: versionIndex, dolbyVisionDisabled: dolbyVisionDisabled),
    ?audioLabel,
  ];
}

/// The format of the version's own audio stream — codec, then channels or
/// Atmos — as [buildMediaQualityLabels] appends it.
///
/// Separately available for the line that names the *chosen* track: when the
/// player's own row has no format to show, the container's is still a fact
/// about the file, and saying it beats saying nothing.
String? buildMediaAudioLabel(MediaItem item, {int versionIndex = 0}) {
  final version = _selectedVersion(item.mediaVersions, versionIndex);
  return version == null ? null : _formatAudio(_selectedAudioStream(version));
}

/// Resolution, bitrate and dynamic range — the picture half of
/// [buildMediaQualityLabels].
///
/// **No video codec.** On the detail hero it stood between the bitrate and the
/// dynamic range without answering anything: the bitrate already says what it
/// was standing in for, and the codec is in the file-info sheet for whoever
/// needs it.
///
/// The dynamic range is what the *display* is handed, so it follows the
/// Dolby-Vision-off switch — see [_formatDynamicRange].
///
/// [includeBitrate] off drops the figure for a line that compares copies by
/// kind ("4K · DV") rather than describing one file.
List<String> buildMediaVideoLabels(
  MediaItem item, {
  int versionIndex = 0,
  int? partIndex,
  bool dolbyVisionDisabled = false,
  bool includeBitrate = true,
}) {
  final version = _selectedVersion(item.mediaVersions, versionIndex);
  if (version == null) return const [];

  final labels = <String>[];
  final resolution = _formatResolution(version);
  if (resolution != null) labels.add(resolution);

  // Right behind the resolution: two 1080p files can differ by a factor of
  // three in bitrate, which is what the line is otherwise silent about.
  if (version.bitrate case final bitrate? when includeBitrate && bitrate > 0) {
    labels.add(ByteFormatter.formatBitrate(bitrate));
  }

  final video = _firstStreamOfKind(version, MediaStreamKind.video, partIndex: partIndex);
  final dynamicRange = _formatDynamicRange(video, dolbyVisionDisabled: dolbyVisionDisabled);
  if (dynamicRange != null) labels.add(dynamicRange);

  return labels;
}

String? buildMediaSizeLabel(MediaItem item, {int versionIndex = 0}) {
  final version = _selectedVersion(item.mediaVersions, versionIndex);
  if (version == null || version.parts.isEmpty) return null;

  var totalBytes = 0;
  for (final part in version.parts) {
    final sizeBytes = part.sizeBytes;
    if (sizeBytes == null || sizeBytes <= 0) return null;
    totalBytes += sizeBytes;
  }

  return ByteFormatter.formatBytes(totalBytes);
}

/// What the display is handed, not what the file is made of.
///
/// With Dolby Vision switched off the base layer is what plays, so the line
/// says so. Profile 5 has no base layer to fall back to and keeps its Dolby
/// Vision label either way.
String? _formatDynamicRange(MediaStream? video, {required bool dolbyVisionDisabled}) {
  if (video == null) return null;
  if (video.dolbyVision && !(dolbyVisionDisabled && video.dolbyVisionProfile != 5)) {
    return _formatDolbyVision(video);
  }
  if (!video.dolbyVision && !video.hdr) return null;
  return video.hdr10Plus ? 'HDR10+' : 'HDR';
}

String _formatDolbyVision(MediaStream stream) {
  final profile = stream.dolbyVisionProfile;
  return profile == null || profile <= 0 ? 'DV' : 'DV P$profile';
}

MediaVersion? _selectedVersion(List<MediaVersion>? versions, int versionIndex) {
  if (versions == null || versions.isEmpty) return null;
  if (versionIndex >= 0 && versionIndex < versions.length) {
    return versions[versionIndex];
  }
  return versions.first;
}

String? _formatResolution(MediaVersion version) {
  final raw = version.videoResolution?.trim();
  if (raw != null && raw.isNotEmpty) return resolutionDisplayLabel(raw);

  final fallback = resolutionLabelFromDimensions(version.width, version.height);
  return fallback == null ? null : resolutionDisplayLabel(fallback);
}

MediaStream? _firstStreamOfKind(MediaVersion version, MediaStreamKind kind, {int? partIndex}) {
  if (partIndex != null && partIndex >= 0 && partIndex < version.parts.length) {
    for (final stream in version.parts[partIndex].streams) {
      if (stream.kind == kind) return stream;
    }
    return null;
  }
  for (final part in version.parts) {
    for (final stream in part.streams) {
      if (stream.kind == kind) return stream;
    }
  }
  return null;
}

MediaStream? _selectedAudioStream(MediaVersion version) {
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

String? _formatAudio(MediaStream? stream) {
  if (stream == null) return null;
  return _formatAudioFormat(
    codec: stream.codec,
    profile: stream.profile,
    channels: stream.channels,
    atmosSources: [stream.codec, stream.title, stream.displayTitle],
  );
}

/// The same format line for a playback row rather than a container stream:
/// what the *codec* fields say, never the muxer's track title.
///
/// The title is often a technical description of its own ("German DTS-HD MA
/// 2.0"), which reads as a duplicate of the format beside it and is long
/// enough to push the whole chip off a fitted line. The language it carries
/// belongs to the track *choice*, which the status line under the buttons
/// states already.
String? buildAudioTrackLabel(MediaAudioTrack track) {
  return _formatAudioFormat(
    codec: track.codec,
    profile: track.profile,
    channels: track.channels,
    atmosSources: [track.codec, track.title, track.displayTitle],
  );
}

String? _formatAudioFormat({
  required String? codec,
  required String? profile,
  required int? channels,
  required List<String?> atmosSources,
}) {
  final parts = <String>[];
  final trimmed = codec?.trim();
  if (trimmed != null && trimmed.isNotEmpty) parts.add(_formatAudioCodec(trimmed, profile));

  if (_namesAtmos(atmosSources)) {
    parts.add('Atmos');
  } else {
    final layout = CodecUtils.formatAudioChannels(channels);
    if (layout != null) parts.add(layout);
  }

  return parts.isEmpty ? null : parts.join(' ');
}

String _formatAudioCodec(String codec, String? profile) {
  return switch (codec.toLowerCase()) {
    'eac3' || 'ec3' => 'EAC3',
    'ac3' => 'AC3',
    _ => CodecUtils.formatAudioCodec(codec, profile: profile),
  };
}

bool _namesAtmos(List<String?> values) {
  return values.whereType<String>().any((value) => value.toLowerCase().contains('atmos'));
}
