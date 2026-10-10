import 'dart:async';
import '../media/ids.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../i18n/strings.g.dart';

import '../media/live_tv_support.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../models/livetv_channel.dart';
import '../models/transcode_quality_preset.dart';
import '../providers/iptv_sources_provider.dart';
import '../providers/multi_server_provider.dart';
import '../screens/video_player/live_tv_session_args.dart';
import '../screens/video_player_screen.dart';
import '../utils/app_logger.dart';
import '../utils/snackbar_helper.dart';
import '../utils/video_player_navigation.dart';
import '../services/live_picture_handover.dart';
import '../services/playback_launch_observer.dart';

/// Navigate to the video player for a live TV channel — the single live
/// entry for both backends. The player starts the backend-neutral
/// `LiveTvPlaybackSession` itself (Plex tune / Jellyfin stream negotiation
/// run under its loading spinner), so this only validates that the
/// channel's server is reachable and packages the UX arguments.
///
/// [channels] is the full channel list for channel up/down navigation.
/// [startPosition] pre-answers the "watch from start" prompt shown when the
/// channel already has recorded history.
///
/// [handover] is the guide's preview, still playing [channel], for the player
/// to take on, and [pictureFrom] the box it plays in (Plebz): the player grows
/// out of it. True once the player route is on its way; on false the caller
/// still owns [handover].
Future<bool> navigateToLiveTv(
  BuildContext context, {
  required MultiServerProvider multiServer,
  required LiveTvChannel channel,
  required List<LiveTvChannel> channels,

  /// Start from the archive at this absolute epoch second instead of live.
  int? startAtEpoch,
  PlaybackLaunchObserver? launchObserver,
  bool Function()? isLaunchCurrent,

  /// The group the launching screen is confined to — see
  /// [LiveTvSessionArgs.initialGroup]. [channels] stays the whole list.
  String? group,
  LiveTvStartPosition startPosition = LiveTvStartPosition.ask,
  LivePictureHandover? handover,
  Rect? pictureFrom,
}) async {
  if (!(isLaunchCurrent?.call() ?? true) || !(launchObserver?.isCurrent ?? true)) return false;
  // An IPTV channel belongs to a playlist, not to a media server: it has no
  // entry in `liveTvServers` and no client, so the server checks below would
  // reject every one of them. The player resolves its session from the same
  // provider (`_startLiveSession`).
  final isIptvChannel = context.read<IptvSourcesProvider?>()?.liveTvForSourceId(channel.serverId ?? '') != null;

  MediaBackend? serverBackend;
  if (!isIptvChannel) {
    final serverInfo = liveTvServerInfoForChannel(multiServer, channel);
    if (serverInfo == null) {
      launchObserver?.mark('blocked', blocker: 'serverUnavailable');
      showErrorSnackBar(context, Translations.of(context).liveTv.serverUnavailable);
      return false;
    }

    final client = multiServer.getClientForServer(ServerId(serverInfo.serverId));
    if (client == null) {
      launchObserver?.mark('blocked', blocker: 'serverUnavailable');
      showErrorSnackBar(context, Translations.of(context).liveTv.serverNotConnected);
      return false;
    }
    serverBackend = client.backend;
  }

  final navigator = Navigator.of(context);
  appLogger.d('Navigating to live channel: ${channel.displayName} (${channel.key})');

  // The placeholder carries the actual backend through so any in-player
  // `metadata.backend` branch (transcoder hints, watch-state surfaces) sees
  // the right kind. An IPTV channel has no backend at all; the live path
  // never branches on it, so it carries the codebase's default for absent
  // values.
  final placeholder = liveTvChannelItem(channel, backend: serverBackend ?? MediaBackend.plex);

  final normalizedChannels = List<LiveTvChannel>.of(channels);
  var currentChannelIndex = normalizedChannels.indexWhere(
    (ch) => liveTvChannelScopeKey(ch) == liveTvChannelScopeKey(channel),
  );
  if (currentChannelIndex < 0) {
    normalizedChannels.insert(0, channel);
    currentChannelIndex = 0;
    appLogger.w('Live TV launch channel was not present in navigation list; prepending ${channel.key}');
  }

  final route = VideoPlayerRoute(
    pictureFrom: handover == null ? null : pictureFrom,
    builder: (_) => VideoPlayerScreen(
      metadata: placeholder,
      live: LiveTvSessionArgs(
        channel: channel,
        channels: normalizedChannels,
        currentChannelIndex: currentChannelIndex,
        startAtEpoch: startAtEpoch,
        initialGroup: group,
        startPosition: startPosition,
        handover: handover,
      ),
      launchObserver: launchObserver,
      isLaunchCurrent: isLaunchCurrent,
    ),
  );

  unawaited(route.push(navigator));
  launchObserver?.mark('opening');
  return true;
}

/// The backend-neutral placeholder item standing in for a tuned live channel.
///
/// Shared by the launch path and the in-player channel zap so the two cannot
/// drift: everything keyed off the screen's current metadata — the OS media
/// session, the client lookups, and the scoped player preferences — has to
/// describe the channel that is actually tuned. [thumbPath] feeds the media
/// session artwork through the same `MediaServerClient.thumbnailUrl` adapter
/// VOD uses, so the Now Playing card carries the channel logo.
///
/// [serverId] overrides the channel's own scope for a channel that does not
/// carry one: the live TV server the tune picks is the one that can serve its
/// logo.
MediaItem liveTvChannelItem(LiveTvChannel channel, {required MediaBackend backend, String? serverId}) {
  return MediaItem(
    id: channel.key,
    backend: backend,
    kind: MediaKind.clip,
    title: channel.displayName,
    serverId: serverId ?? channel.serverId,
    serverName: channel.serverName,
    thumbPath: channel.thumb ?? channel.art,
    raw: {'key': channel.key},
  );
}

/// Resolves the Live TV backend without weakening explicit channel ownership.
///
/// A channel scoped to a server and DVR must match that exact pair. A channel
/// scoped only to a server may use any DVR on that server. Only an unscoped
/// channel may retain the first-server fallback.
LiveTvServerInfo? liveTvServerInfoForChannel(MultiServerProvider multiServer, LiveTvChannel channel) {
  final serverId = channel.serverId;
  if (serverId == null) return multiServer.liveTvServers.firstOrNull;

  final dvrKey = channel.liveDvrKey;
  if (dvrKey != null) {
    return multiServer.liveTvServers.where((s) => s.serverId == serverId && s.dvrKey == dvrKey).firstOrNull;
  }
  return multiServer.liveTvServers.where((s) => s.serverId == serverId).firstOrNull;
}

/// Start a playback session for [channel], whoever owns it.
///
/// The single place that knows a live channel can come from an IPTV playlist
/// as well as from a media server, and that the playlist has to be asked
/// first: an IPTV channel has no entry in `liveTvServers`, so the server
/// lookup would find nothing for it and report the wrong reason.
///
/// Returns null when nothing can serve the channel; the caller decides
/// whether that is worth a message.
Future<LiveTvPlaybackSession?> startLiveTvSession(
  BuildContext context,
  LiveTvChannel channel, {
  TranscodeQualityPreset quality = TranscodeQualityPreset.original,
}) async {
  final iptv = context.read<IptvSourcesProvider?>()?.liveTvForSourceId(channel.serverId ?? '');
  if (iptv != null) return iptv.startPlayback(channel.key);

  final multiServer = context.read<MultiServerProvider>();
  final serverInfo = liveTvServerInfoForChannel(multiServer, channel);
  if (serverInfo == null) {
    appLogger.w('No live TV server available for ${channel.displayName}');
    return null;
  }
  final client = multiServer.getClientForServer(ServerId(serverInfo.serverId));
  if (client == null) {
    appLogger.w('Live TV server ${serverInfo.serverId} is not connected');
    return null;
  }
  return client.liveTv.startPlayback(channel.key, dvrKey: serverInfo.dvrKey, quality: quality);
}
