import '../../models/livetv_channel.dart';
import '../../services/live_picture_handover.dart';

/// Launch parameters for a live TV session — pure UX data. A
/// [VideoPlayerScreen] plays live TV iff it was constructed with one of
/// these.
///
/// Transport (tune/stream-URL resolution, session identity) is no longer
/// passed in: the player starts a backend-neutral `LiveTvPlaybackSession`
/// via `client.liveTv.startPlayback` itself, for both backends, so launch
/// and channel zapping share one resolution path and one spinner UX.
/// How to start a channel that already has recorded history (an in-progress
/// DVR recording or an existing capture session).
enum LiveTvStartPosition {
  /// Ask the user whether to start from the beginning or join live.
  ask,

  /// Start from the beginning of the current program without asking.
  beginning,

  /// Join at the live edge without asking.
  live,
}

class LiveTvSessionArgs {
  /// The channel to start on.
  final LiveTvChannel channel;

  /// Full channel list for channel up/down navigation.
  final List<LiveTvChannel>? channels;

  /// Index of [channel] within [channels] (-1 / null when unknown).
  final int? currentChannelIndex;

  /// Where to start, as an absolute epoch second, for a programme picked out
  /// of the archive. Null starts at the live edge, which is every other way
  /// into the player.
  final int? startAtEpoch;

  /// The group the session starts confined to, or null for all of them.
  ///
  /// The screen that launched this was very likely showing one group, and the
  /// viewer expects channel up and down to stay in it. It is passed as a
  /// *state*, not as a pre-filtered [channels] list: the player's group list
  /// is built from what it was handed, so a screen that narrowed the list
  /// first left the player with one group and nothing to offer — which is
  /// exactly the thing RIGHT exists to open.
  final String? initialGroup;

  /// How to handle recorded history on the first tune. Channel zaps inside
  /// the player always ask.
  final LiveTvStartPosition startPosition;

  /// The guide's preview, still playing [channel], for the player to take on
  /// instead of opening the channel again (Plebz). The screen owns it from
  /// construction: it plays it on, or releases it if it never gets that far.
  final LivePictureHandover? handover;

  const LiveTvSessionArgs({
    required this.channel,
    this.channels,
    this.currentChannelIndex,
    this.startAtEpoch,
    this.initialGroup,
    this.startPosition = LiveTvStartPosition.ask,
    this.handover,
  });
}
