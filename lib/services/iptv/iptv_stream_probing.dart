import '../../media/live_tv_support.dart';
import '../../mpv/mpv.dart';
import '../../utils/app_logger.dart';
import 'iptv_live_tv_source.dart' show IptvPlaybackSession;

/// How many seconds of an IPTV live stream mpv's demuxer studies before it
/// plays it (Plebz, faster zapping).
///
/// FFmpeg reads a transport stream until every stream it announces has shown
/// its parameters, or until its limit runs out — seven seconds of stream for
/// MPEG-TS, which on a live channel is seven seconds of waiting. A playlist
/// channel routinely announces streams that send little or nothing (an idle
/// second audio, a sparse data stream), and then each zap runs to that limit.
/// 1.5 s still covers a group of pictures of the usual length, so the
/// picture's own parameters are found and the hardware decoder can be set up;
/// what it may cost is a track that sent nothing in that time showing up
/// without its details until it does.
const String iptvAnalyzeDurationSeconds = '1.5';

/// Applies [iptvAnalyzeDurationSeconds] before the next open of an IPTV
/// stream, and mpv's own default (`0`) before any other: the full-screen
/// player can zap from a playlist channel to a server's. A refusal leaves mpv
/// on whatever it had; the stream opens either way.
Future<void> applyLiveStreamProbing(Player player, LiveTvPlaybackSession? session) async {
  try {
    await player.setProperty(
      'demuxer-lavf-analyzeduration',
      session is IptvPlaybackSession ? iptvAnalyzeDurationSeconds : '0',
    );
  } catch (e) {
    appLogger.d('Live stream probing not applied', error: e);
  }
}
