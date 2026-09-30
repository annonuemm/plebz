import '../models/livetv_channel.dart';
import '../models/livetv_program.dart';

bool liveTvProgramMatchesChannel(LiveTvProgram program, LiveTvChannel channel) {
  final programChannel = liveTvNonEmpty(program.channelIdentifier);
  if (programChannel == null) return false;
  if (programChannel != channel.key && programChannel != channel.identifier) return false;

  if (!_nullableIdsMatch(program.serverId, channel.serverId)) return false;
  if (!_nullableIdsMatch(program.liveDvrKey, channel.liveDvrKey)) return false;

  final programProvider = liveTvNonEmpty(program.providerIdentifier);
  final channelProvider = liveTvProviderIdentifierForChannel(channel);
  if (programProvider != null && channelProvider != null && programProvider != channelProvider) return false;

  return true;
}

String? liveTvProviderIdentifierForChannel(LiveTvChannel channel) {
  final source = liveTvNonEmpty(channel.favoriteSource);
  if (source != null) {
    final uri = Uri.tryParse(source);
    if (uri != null && uri.pathSegments.isNotEmpty) return liveTvNonEmpty(uri.pathSegments.last);

    final slashIndex = source.lastIndexOf('/');
    if (slashIndex >= 0 && slashIndex < source.length - 1) {
      return liveTvNonEmpty(source.substring(slashIndex + 1));
    }
  }
  return liveTvNonEmpty(channel.lineup);
}

bool _nullableIdsMatch(String? a, String? b) {
  final left = liveTvNonEmpty(a);
  final right = liveTvNonEmpty(b);
  return left == null || right == null || left == right;
}

/// Trimmed [value], or null when it is null, empty, or whitespace-only.
String? liveTvNonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Whether [channel]'s archive still covers the start of [program].
///
/// Two conditions: the provider keeps an archive at all, and the programme
/// began inside the window it keeps. Deliberately not restricted to finished
/// programmes — what is on right now has already been broadcast up to this
/// minute, and that part is in the archive, which is exactly what starting it
/// from the beginning needs. Something that has not started has nothing to
/// play.
bool liveTvProgramIsArchived(LiveTvChannel channel, LiveTvProgram program, {DateTime? now}) {
  final days = channel.catchupDays;
  final beginsAt = program.beginsAt;
  if (days == null || beginsAt == null) return false;

  final at = now ?? DateTime.now();
  if (beginsAt >= at.millisecondsSinceEpoch ~/ 1000) return false;
  return beginsAt >= at.subtract(Duration(days: days)).millisecondsSinceEpoch ~/ 1000;
}

/// How long a programme must have been running before starting it over is
/// worth offering. Below this, "from the beginning" is where the viewer
/// already is.
const liveTvRestartThreshold = Duration(minutes: 1);

/// The group a channel belongs to — a playlist's `group-title`, an Xtream
/// category — or null where it has none.
///
/// The one place that answers this, so the guide's group bar, the player's
/// group list and the arrangement sheet cannot drift into three ideas of what
/// a group is.
String? liveTvChannelGroup(LiveTvChannel channel) => liveTvNonEmpty(channel.lineup);
