import '../media/media_display_criteria.dart';
import '../utils/json_utils.dart';

MediaDisplayCriteria? jellyfinDisplayCriteriaFromStream(
  Map<String, dynamic> source,
  Map<String, dynamic>? videoStream,
) {
  if (videoStream == null) return null;

  final doviProfile = flexibleInt(videoStream['DvProfile']);
  final doviCompatibilityId = flexibleInt(videoStream['DvBlSignalCompatibilityId']);
  final videoRangeType = videoStream['VideoRangeType']?.toString().toLowerCase();
  final videoRange = videoStream['VideoRange']?.toString().toLowerCase();
  final transfer = _stringOrNull(videoStream['ColorTransfer']);
  final primaries = _stringOrNull(videoStream['ColorPrimaries']);
  final matrix = _stringOrNull(videoStream['ColorSpace']);
  final range = '${videoRangeType ?? ''} ${videoRange ?? ''}';
  final defaults = classifyMediaDisplayColor(
    isDolbyVision: (doviProfile ?? 0) > 0,
    doviCompatibilityId: doviCompatibilityId,
    range: range,
    transfer: transfer,
    primaries: primaries,
    matrix: matrix,
    assumeSdr: range.trim().isEmpty,
  ).defaultTags;
  final criteria = MediaDisplayCriteria.fromRaw(
    fps: videoStream['RealFrameRate'] ?? videoStream['AverageFrameRate'],
    width: videoStream['Width'] ?? source['Width'],
    height: videoStream['Height'] ?? source['Height'],
    doviProfile: doviProfile,
    doviLevel: videoStream['DvLevel'],
    doviCompatibilityId: doviCompatibilityId,
    transfer: transfer ?? defaults.transfer,
    primaries: primaries ?? defaults.primaries,
    matrix: matrix ?? defaults.matrix,
  );
  return criteria.isUsable ? criteria : null;
}

bool jellyfinVideoStreamIsDolbyVision(Map<String, dynamic> videoStream) {
  final profile = jellyfinDolbyVisionProfile(videoStream);
  if (profile != null && profile > 0) return true;
  if ((flexibleInt(videoStream['DvVersionMajor']) ?? 0) > 0) return true;
  if ((flexibleInt(videoStream['DvVersionMinor']) ?? 0) > 0) return true;

  final text = [
    videoStream['VideoRangeType'],
    videoStream['VideoRange'],
    videoStream['VideoDoViTitle'],
  ].whereType<Object>().map((value) => value.toString().toLowerCase()).join(' ');
  return text.contains('dovi') || text.contains('dolby vision') || text.contains('dolbyvision');
}

int? jellyfinDolbyVisionProfile(Map<String, dynamic> videoStream) => flexibleInt(videoStream['DvProfile']);

/// Whether the stream carries dynamic HDR10+ metadata.
///
/// Jellyfin says so twice and neither is reliable alone: `Hdr10PlusPresentFlag`
/// is only filled in by newer probes, and `VideoRangeType` collapses to plain
/// `HDR10` whenever Dolby Vision is present as well.
bool jellyfinVideoStreamIsHdr10Plus(Map<String, dynamic> videoStream) {
  if (flexibleBool(videoStream['Hdr10PlusPresentFlag'])) return true;
  final type = videoStream['VideoRangeType']?.toString().toLowerCase() ?? '';
  return type.contains('hdr10plus');
}

bool jellyfinVideoStreamIsHdr(Map<String, dynamic> source, Map<String, dynamic> videoStream) {
  if (jellyfinVideoStreamIsDolbyVision(videoStream)) return true;
  final criteria = jellyfinDisplayCriteriaFromStream(source, videoStream);
  if (criteria?.isHdr == true) return true;

  final range = [
    videoStream['VideoRangeType'],
    videoStream['VideoRange'],
  ].whereType<Object>().map((value) => value.toString().toLowerCase()).join(' ');
  return range.contains('hdr') || range.contains('hlg');
}

String? _stringOrNull(Object? value) {
  final string = value?.toString().trim();
  return string == null || string.isEmpty ? null : string;
}
