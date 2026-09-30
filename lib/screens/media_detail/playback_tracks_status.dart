part of '../media_detail_screen.dart';

/// The action row's trailing status: what Play will do with this item's
/// picture, audio, and subtitles, computed by the player's own selection
/// ladder ([previewPlaybackTracks]). Read-only — it describes the episode the
/// hero shows, and on TV that changes with rail focus, so there is no per-
/// episode target for a control here to act on.
extension _MediaDetailPlaybackTracksStatus on _MediaDetailScreenState {
  /// The item Play would start: the hero's episode for a show, the first
  /// episode for a season, the item itself otherwise. Null while a show has
  /// not resolved any episode yet.
  MediaItem? _playbackTargetItem(MediaItem metadata) {
    if (!_canUseDetail) return null;
    final MediaItem? target;
    if (metadata.isShow) {
      target = _showPlayEpisode();
    } else if (metadata.isSeason) {
      target = _episodes.isEmpty ? null : _episodes.first;
    } else {
      target = metadata;
    }
    return target;
  }

  Future<void> _listenForPlaybackVersionChanges() async {
    final settings = await SettingsService.getInstance();
    if (!_canUseDetail) return;
    bindListenable(settings.listenableOf(SettingsService.mediaVersionPreferences), _onPlaybackVersionChanged);
  }

  void _onPlaybackVersionChanged() {
    if (!_canUseDetail) return;
    _invalidatePlaybackProbes(refreshItems: false);
  }

  void _invalidatePlaybackProbes({required bool refreshItems}) {
    _playbackProbeGeneration++;
    _playbackProbeTimer?.cancel();
    _playbackProbeRequests.clear();
    _playbackSources.clear();
    if (refreshItems) _probedPlaybackItems.clear();
    _playbackStatusRevision.value++;
  }

  /// Fetch metadata once, then resolve the saved selection independently.
  /// Rendering never starts PlaybackInfo or a transcode. Offline only reads
  /// the completed download's identity, never a server or track probe.
  void _scheduleTargetProbe(BuildContext context, MediaItem target) {
    if (!_canUseDetail) return;
    final key = target.globalKey;
    if (_playbackSources.containsKey(key) || _playbackProbeRequests.containsKey(key)) return;
    final client = widget.isOffline ? null : _getMediaClientForMetadata(context);
    if (!widget.isOffline && client == null) return;
    final downloads = widget.isOffline ? context.read<DownloadProvider>() : null;
    _playbackProbeTimer?.cancel();
    final generation = _playbackProbeGeneration;
    _playbackProbeTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || generation != _playbackProbeGeneration || _playbackProbeRequests.containsKey(key)) return;
      unawaited(_probeTarget(client, downloads, target, generation));
    });
  }

  Future<void> _probeTarget(
    MediaServerClient? client,
    DownloadProvider? downloads,
    MediaItem target,
    int generation,
  ) async {
    final key = target.globalKey;
    final request = Object();
    _playbackProbeRequests[key] = request;
    bool current() => _canUseDetail && generation == _playbackProbeGeneration && _playbackProbeRequests[key] == request;
    try {
      MediaItem item;
      MediaSourceInfo? source;
      int? mediaIndex;
      if (downloads != null) {
        final downloaded = await downloads.getCompletedDownload(key);
        if (!current()) return;
        item = target;
        if (downloaded != null) {
          final versions = item.mediaVersions;
          final byId = downloaded.mediaSourceId == null
              ? -1
              : versions?.indexWhere((version) => version.id == downloaded.mediaSourceId) ?? -1;
          mediaIndex = byId >= 0 ? byId : downloaded.mediaIndex;
          if (versions == null || mediaIndex < 0 || mediaIndex >= versions.length) mediaIndex = null;
        }
      } else {
        final fetched = _probedPlaybackItems[key] ?? await client!.fetchItem(target.id);
        if (!current() || fetched == null) return;
        item = fetched.copyWith(
          serverId: target.serverId ?? fetched.serverId,
          serverName: target.serverName ?? fetched.serverName,
        );
        _probedPlaybackItems[key] = item;
        final selection = await resolveSavedMediaVersionFor(item);
        if (!current()) return;
        source = await client!.fetchCachedMediaSourceInfo(
          item.id,
          mediaIndex: selection?.index ?? 0,
          mediaSourceId: selection?.sourceId,
          preferredVersionSignature: selection?.signature,
        );
        if (!current() || source == null) return;
        mediaIndex = source.mediaIndex ?? selection?.index ?? 0;
      }
      if (!current()) return;
      _playbackSources[key] = (item: item, source: source, mediaIndex: mediaIndex);
      // Only the status repaints: do not rebuild the rail or replace its
      // focused item with a cached probe snapshot.
      _playbackStatusRevision.value++;
    } catch (e, stackTrace) {
      appLogger.d('Playback track probe failed for ${target.id}', error: e, stackTrace: stackTrace);
    } finally {
      if (_playbackProbeRequests[key] == request) _playbackProbeRequests.remove(key);
    }
  }

  /// What Play would start with, for the two lines that describe it: the
  /// hero's facts row takes the *quality* (picture, and the format of the
  /// chosen audio row), the status line under the buttons takes the *choice*
  /// (which language, and what happens with subtitles).
  ///
  /// Both readers schedule the probe, and it is safe for both to: the
  /// scheduler returns immediately when a source is already resolved or a
  /// request is already out, and the one it does start is debounced.
  ///
  /// The facts row used to be a pure reader, which coupled it to a setting
  /// about a different line: with the track status switched off nothing
  /// started the probe, and the hero silently lost its resolution, codec,
  /// dynamic range and audio format along with it. Two lines that describe
  /// the same file must not depend on each other to exist.
  ({List<String> videoLabels, String? containerAudioLabel, PlaybackTrackPreview? preview})? _resolvedPlayback(
    BuildContext context,
    MediaItem metadata, {
    bool schedule = false,
  }) {
    final target = _playbackTargetItem(metadata);
    if (target == null) return null;

    final probed = _playbackSources[target.globalKey];
    final source = probed?.source;
    // Profile-scoped in the app; nullable so a bare detail screen (widget
    // tests) still previews with the ladder's non-profile tiers.
    final preview = source == null
        ? null
        : previewPlaybackTracks(
            probed!.item,
            source,
            profile: context.watch<AccountPreferencesController?>()?.activePreferences,
          );
    final videoLabels = probed?.mediaIndex == null
        ? const <String>[]
        : buildMediaVideoLabels(
            probed!.item,
            versionIndex: probed.mediaIndex!,
            partIndex: source?.partIndex,
            // What the display is handed, not what the file holds: with the
            // switch on, media3 plays the base layer and the row says so.
            dolbyVisionDisabled: _dolbyVisionDisabled,
          );
    // What the file itself carries, for the rows the probe cannot describe:
    // a source that came back without audio rows, or with a row that names
    // neither codec nor channels, would otherwise drop the format silently.
    final containerAudioLabel = probed?.mediaIndex == null
        ? null
        : buildMediaAudioLabel(probed!.item, versionIndex: probed.mediaIndex!);
    if (probed == null && schedule) _scheduleTargetProbe(context, target);
    return (videoLabels: videoLabels, containerAudioLabel: containerAudioLabel, preview: preview);
  }

  /// Resolution, bitrate, codec, dynamic range, and the format of the audio
  /// row the ladder picks — the facts about the file, for the hero's line.
  ///
  /// The language is deliberately absent: it is a choice, not a quality, and
  /// it is what the status line under the buttons exists to say.
  ///
  /// The format is read off the row's codec fields ([buildAudioTrackLabel]),
  /// not off its display label: the label leads with the muxer's track title,
  /// which repeats the format in the muxer's own words and is long enough to
  /// push the chip off the fitted line entirely. A row that names no format
  /// falls back to the container's own audio stream, the same file's fact by
  /// a different route.
  List<String> _playbackQualityLabels(BuildContext context, MediaItem metadata) {
    final resolved = _resolvedPlayback(context, metadata, schedule: true);
    if (resolved == null) return const [];
    final row = resolved.preview?.audio;
    final audioFormat = (row == null ? null : buildAudioTrackLabel(row)) ?? resolved.containerAudioLabel;
    return [...resolved.videoLabels, ?audioFormat];
  }

  /// The listener stays mounted while a source is resolving, without adding
  /// a semantic or focus target when there is nothing to predict.
  Widget _buildPlaybackTracksStatus(
    BuildContext context,
    MediaItem metadata, {
    required bool isTv,
    required double tvScale,
    required double maxWidth,
  }) {
    // Switched off, the line is not drawn and not computed: resolving which
    // track Play would pick walks the item's streams, and there is no reason
    // to walk them for something nobody is going to read. Watched rather than
    // read once, so the corner appears and disappears with the switch instead
    // of at the next screen.
    return SettingValueBuilder<bool>(
      pref: SettingsService.showPlaybackTracksStatus,
      builder: (context, show, _) {
        if (!show) return const SizedBox.shrink();
        return ValueListenableBuilder<int>(
          valueListenable: _playbackStatusRevision,
          builder: (context, _, _) =>
              _playbackTracksStatus(context, metadata, isTv: isTv, tvScale: tvScale, maxWidth: maxWidth) ??
              const SizedBox.shrink(),
        );
      },
    );
  }

  Widget? _playbackTracksStatus(
    BuildContext context,
    MediaItem metadata, {
    required bool isTv,
    required double tvScale,
    required double maxWidth,
  }) {
    final target = _playbackTargetItem(metadata);
    if (target == null) return null;
    if (_playbackStatusTarget != target.globalKey) {
      _playbackStatusTarget = target.globalKey;
      final cached = _playbackSources[target.globalKey]?.source;
      if (!widget.isOffline && cached != null && !mediaSourceHasTrackRows(cached)) {
        _playbackSources.remove(target.globalKey);
      }
    }

    final resolved = _resolvedPlayback(context, metadata, schedule: true);
    final preview = resolved?.preview;
    if (preview == null) return null;

    final audioLabel = preview.audio?.label;
    final subtitleLabel = preview.subtitle?.label;
    // Only the choice, not the file: which language is coming out of the
    // speakers, and what the subtitles are doing. The picture and the codecs
    // moved to the hero's facts row, which has half again the width for them
    // and where they sit beside the year and the runtime they belong with.
    //
    // Both labels are primary-only. A subtitle row that is forced says so in
    // its primary already (TrackLabelBuilder folds the flag in); the
    // secondaries are the codecs, which are quality, not choice.
    final parts = <MetadataLinePart>[
      // The subtitle decision always stays: it is the one of the two that can
      // surprise, since an audio track is always playing.
      if (audioLabel != null) MetadataLineIconText(Symbols.volume_up_rounded, audioLabel.primary, dropPriority: 1),
      MetadataLineIconText(Symbols.subtitles_rounded, subtitleLabel?.primary ?? t.common.off, dropPriority: 0),
    ];
    final semanticsLabel =
        '${t.videoControls.tracksButton}: ${[for (final part in parts) switch (part) {
            MetadataLineText(:final text) => text,
            MetadataLineIconText(:final text, :final detail) => detail == null ? text : '$text${MetadataLineIconText.detailSeparator}$detail',
            MetadataLineRatings() => '',
          }].join(', ')}';

    // Same ink as the hero's metadata line, one step lighter in weight and
    // size so it reads as a footnote to the buttons rather than a sixth one.
    final textStyle = TextStyle(
      color: isTv ? _tvDetailForegroundColor(context) : Theme.of(context).colorScheme.onSurface,
      fontSize: isTv ? 15 * tvScale : 12.5,
      fontWeight: .w600,
      letterSpacing: 0.1,
      height: 1.2,
    );

    return Semantics(
      key: const ValueKey('detail_playback_tracks'),
      label: semanticsLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: FittedMetadataLine(
          textStyle: monoFacts(context, textStyle),
          parts: parts,
          // Boxed like the hero's facts row across the screen from it, so the
          // two lines that frame the action row are read the same way — under
          // "Glas" capsules of glass, as the hero draws them. The outlines
          // also cost less width than the bullets they replace, which is width
          // this line spends on a codec detail.
          chipped: true,
          chipSpacing: isTv ? 8 * tvScale : 6,
          ratingIconSize: textStyle.fontSize! * 1.15,
        ),
      ),
    );
  }
}
