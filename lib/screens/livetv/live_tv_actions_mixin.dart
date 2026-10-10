import 'dart:async';

import 'package:flutter/material.dart';
import '../../media/ids.dart';
import 'package:provider/provider.dart';

import '../../models/livetv_channel.dart';
import '../../models/livetv_program.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/live_picture_handover.dart';
import '../../utils/live_tv_matching.dart';
import '../../utils/live_tv_player_navigation.dart';
import '../../utils/media_image_helper.dart';
import 'program_details_sheet.dart';

/// Shared live-TV actions: channel lookup, tuning, and program-details sheet.
///
/// Implementers expose their channel list via [liveTvChannels] and invoke
/// [findChannelForProgram], [tuneChannel], and [showProgramDetails] as needed.
mixin LiveTvActionsMixin<T extends StatefulWidget> on State<T> {
  /// Channel list used for lookups — what this screen is showing.
  List<LiveTvChannel> get liveTvChannels;

  /// The list the *player* should navigate, which is not the same question.
  ///
  /// A screen usually shows one group; the player has to be able to leave it,
  /// because its RIGHT key opens the group list and that list is built from
  /// what it was handed. So a screen that narrows by group hands over the
  /// unnarrowed list here and names the group in [liveTvPlayerGroup] instead —
  /// the player then narrows itself, through the one mechanism it has for it.
  /// Filters that are not groups (favourites) belong in this list, because the
  /// player has no notion of them and no way to restore one.
  List<LiveTvChannel> get liveTvPlayerChannels => liveTvChannels;

  /// The group [liveTvPlayerChannels] should start confined to.
  String? get liveTvPlayerGroup => null;

  LiveTvChannel? findChannelForProgram(LiveTvProgram program) {
    return liveTvChannels.where((channel) => liveTvProgramMatchesChannel(program, channel)).firstOrNull;
  }

  /// Start live playback for [channel] on its owning server.
  ///
  /// Both backends route through the live-TV navigator so the player
  /// inherits the live-only branches (no Trakt scrobble, no progress
  /// scrobble, channel up/down nav, no resume bookmark). The player starts
  /// the backend-neutral session itself (Plex tune / Jellyfin stream
  /// negotiation under its loading spinner).
  ///
  /// [handover] and [pictureFrom] carry the guide's playing preview into the
  /// player (see [navigateToLiveTv]). False when the player was not opened,
  /// which leaves [handover] with the caller.
  Future<bool> tuneChannel(
    LiveTvChannel channel, {
    int? startAtEpoch,
    LivePictureHandover? handover,
    Rect? pictureFrom,
  }) {
    final multiServer = context.read<MultiServerProvider>();
    return navigateToLiveTv(
      context,
      multiServer: multiServer,
      channel: channel,
      channels: liveTvPlayerChannels,
      startAtEpoch: startAtEpoch,
      group: liveTvPlayerGroup,
      handover: handover,
      pictureFrom: pictureFrom,
    );
  }

  /// Open the program-details bottom sheet. The poster is resolved from
  /// [posterThumb] on the server identified by [posterServerId].
  void showProgramDetails({
    BuildContext? sheetContext,
    required LiveTvProgram program,
    required LiveTvChannel? channel,
    required String? posterThumb,
    required String? posterServerId,
    ValueChanged<bool>? onRecordingStateChanged,
  }) {
    final effectiveContext = sheetContext ?? context;
    final multiServer = effectiveContext.read<MultiServerProvider>();
    final serverId = serverIdOrNull(posterServerId);
    final client = serverId == null ? null : multiServer.getClientForServer(serverId);
    String? posterUrl;
    if (posterThumb != null && client != null) {
      posterUrl = MediaImageHelper.getOptimizedImageUrl(
        client: client,
        thumbPath: posterThumb,
        maxWidth: 80,
        maxHeight: 120,
        pixelRatio: MediaImageHelper.artworkPixelRatio(effectiveContext),
        imageType: ImageType.poster,
      );
    }

    // The archive is addressed by time, and the programme's own start is the
    // time the viewer means — for a finished programme and for one that has
    // been running long enough to have a beginning worth going back to.
    final beginsAt = program.beginsAt;
    final startedLongEnoughAgo =
        beginsAt != null &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(beginsAt * 1000)) > liveTvRestartThreshold;
    final archived = channel != null && startedLongEnoughAgo && liveTvProgramIsArchived(channel, program);

    showProgramDetailsSheet(
      effectiveContext,
      program: program,
      channel: channel,
      posterUrl: posterUrl,
      onTuneChannel: channel != null ? () => tuneChannel(channel) : null,
      onWatchFromArchive: archived ? () => unawaited(tuneChannel(channel, startAtEpoch: beginsAt)) : null,
      client: client,
      onRecordingStateChanged: onRecordingStateChanged,
    );
  }
}
