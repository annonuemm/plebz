import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_action_bar.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../media/trailer_stage_selection.dart';
import '../../mpv/mpv.dart';
import '../../mpv/player/platform/player_android.dart';
import '../../mpv/player/platform/player_android_mpv.dart';
import '../../redesign/ocker_skin.dart';
import '../../theme/mono_tokens.dart';
import '../../services/playback_coordinator.dart';
import '../../services/settings_service.dart';
import '../../services/trailer_stage_queue.dart';
import '../../utils/app_logger.dart';
import '../../media/media_item_types.dart';
import '../../utils/content_utils.dart';
import '../../utils/media_image_helper.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/fitted_metadata_line.dart';
import '../../widgets/media_rating_badge.dart';
import '../../widgets/loading_indicator_box.dart';
import '../../widgets/optimized_media_image.dart';
import '../media_detail_screen.dart';
import 'trailer_stage_setup_screen.dart';

/// One trailer after another, full screen, for whatever the viewer asked for.
///
/// The stage plays the trailer extras the servers hold, through
/// [MediaServerClient.resolveExternalPlaybackUrl] rather than the playback
/// funnel: a trailer opens no transcode session and reports no progress, so an
/// evening here leaves no trace in the server's dashboard or on a tracker.
///
/// There is one native video core in the app, so the stage holds it the way
/// every other picture does — registered with [PlaybackCoordinator], released
/// the moment something else needs it.
class TrailerStageScreen extends StatefulWidget {
  const TrailerStageScreen({super.key, required this.libraries, required this.selection});

  final List<TrailerStageLibrary> libraries;
  final TrailerStageSelection selection;

  /// Stops short of building the native player so a widget test can drive the
  /// surrounding behaviour — what the overlay says, what the buttons do —
  /// without a playback core it has no way to provide.
  @visibleForTesting
  static bool debugSuppressPlayback = false;

  @override
  State<TrailerStageScreen> createState() => _TrailerStageScreenState();
}

class _TrailerStageScreenState extends State<TrailerStageScreen> with WidgetsBindingObserver {
  late final TrailerStageQueue _queue = TrailerStageQueue(libraries: widget.libraries, selection: widget.selection);

  Player? _player;
  TrailerStageEntry? _current;
  StreamSubscription<bool>? _completion;
  StreamSubscription<bool>? _playingState;

  bool _isPlaying = true;
  bool _isAdvancing = true;
  bool _exhausted = false;
  bool _disposed = false;

  /// Bumped by every advance, so a slow start that resolves after the viewer
  /// pressed on cannot open the wrong trailer.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_advance());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A trailer has nothing to say in the background, and it would hold the
    // native core there.
    if (state != AppLifecycleState.resumed) {
      unawaited(_stopPlayer());
      return;
    }
    unawaited(_resumeCurrent());
  }

  /// Put the picture back after something else had the core.
  ///
  /// The stage lets go of the core whenever it must — the app going to the
  /// background, a player starting somewhere else — and a stage that came
  /// back to its own overlay over nothing would look broken. The trailer
  /// starts again from the top, which is the only position a trailer has.
  Future<void> _resumeCurrent() async {
    final entry = _current;
    if (_disposed || entry == null || _player != null || _isAdvancing) return;
    setState(() => _isAdvancing = true);
    await _start(entry, ++_generation);
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopPlayer());
    _queue.dispose();
    super.dispose();
  }

  Future<void> _stopPlayer() async {
    _generation++;
    unawaited(_completion?.cancel());
    unawaited(_playingState?.cancel());
    _completion = null;
    _playingState = null;
    final player = _player;
    if (player == null) return;
    _player = null;
    PlaybackCoordinator.instance.unregisterInlineVideo(_stopPlayer);
    if (!_disposed && mounted) setState(() {});
    try {
      await player.dispose();
    } catch (e) {
      appLogger.d('Trailer stage: dispose failed', error: e);
    }
  }

  /// The next trailer: stop what is playing, find one, start it.
  ///
  /// The cover stays over the picture for the whole switch. There is one
  /// native core, so the next trailer cannot be prepared while this one plays
  /// — the second or so it takes is a fact of the device, and the cover is
  /// what turns it from a black flash into a title card.
  Future<void> _advance() async {
    if (_disposed) return;
    setState(() => _isAdvancing = true);
    await _stopPlayer();
    final generation = ++_generation;
    final entry = await _queue.next();
    if (_disposed || generation != _generation) return;
    if (entry == null) {
      setState(() {
        _exhausted = true;
        _isAdvancing = false;
        _current = null;
      });
      return;
    }
    setState(() => _current = entry);
    await _start(entry, generation);
  }

  Future<void> _start(TrailerStageEntry entry, int generation) async {
    if (TrailerStageScreen.debugSuppressPlayback) {
      if (mounted && generation == _generation) setState(() => _isAdvancing = false);
      return;
    }
    try {
      // The one native core: whatever holds it lets go first.
      await PlaybackCoordinator.instance.claimVideo();
      if (!mounted || generation != _generation) return;

      final settings = await SettingsService.getInstance();
      final player = Player(useExoPlayer: settings.read(SettingsService.useExoPlayer));
      // Before the first call that builds the native surface: the layer a
      // surface is composited in is read once, when it is made, and cannot be
      // changed afterwards. Without this the picture is born *behind* the
      // Flutter view, where this screen's own black background hides it — the
      // sound plays and the screen stays black.
      switch (player) {
        case PlayerAndroid():
          player.inlineSurface = true;
          // Tunneled video lives on a hardware plane the app cannot place; a
          // picture with an overlay on it has to be composited the ordinary way.
          await player.setProperty('tunneled-playback', 'no');
        case PlayerAndroidMpv():
          player.inlineSurface = true;
        default:
          break;
      }
      if (!mounted || generation != _generation) {
        await player.dispose();
        return;
      }
      _player = player;
      PlaybackCoordinator.instance.registerInlineVideo(stopAndDispose: _stopPlayer);

      // Armed before open: a short trailer can reach its end before anything
      // is listening for it.
      _completion = player.streams.completed.listen((completed) {
        if (!completed || generation != _generation) return;
        unawaited(_advance());
      });
      _playingState = player.streams.playing.listen((playing) {
        if (!mounted || generation != _generation) return;
        setState(() => _isPlaying = playing);
      });

      await player.open(Media(entry.url));
      if (!mounted || generation != _generation) return;
      setState(() {
        _isPlaying = true;
        _isAdvancing = false;
      });
    } catch (e, stackTrace) {
      appLogger.w('Trailer stage: ${entry.item.title} could not start', error: e, stackTrace: stackTrace);
      if (!mounted || generation != _generation) return;
      // A trailer that will not open is not the end of the evening; the next
      // one usually plays.
      unawaited(_advance());
    }
  }

  /// The client this item came from, for its artwork. The stage already holds
  /// the list, so there is no provider lookup to do.
  MediaServerClient? _clientFor(MediaItem item) {
    for (final library in widget.libraries) {
      if (library.client.serverId == item.serverId) return library.client;
    }
    return null;
  }

  Future<void> _togglePause() async {
    final player = _player;
    if (player == null) return;
    await player.playOrPause();
  }

  void _openDetail() {
    final item = _current?.item;
    if (item == null) return;
    // Pausing rather than stopping: the detail page is a look at what is
    // playing, and coming back to a trailer that ran on without you is worse
    // than coming back to a held frame.
    unawaited(_player?.pause());
    unawaited(
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => MediaDetailScreen(metadata: item)))
          // Playing something from the detail page takes the core, and the
          // stage's picture goes with it. Coming back, it starts again.
          .then((_) => _resumeCurrent()),
    );
  }

  void _chooseAgain() {
    TrailerStageSession.reset();
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const TrailerStageSetupScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (player != null)
            Video(player: player, controls: (_) => _buildOverlay(context))
          else
            _buildOverlay(context),
          // Over everything, including the picture: during a switch the old
          // frame is gone and the new one has not arrived.
          if (_isAdvancing || _exhausted) _buildCover(context),
        ],
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final entry = _current;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The facts sit on their own gradient: a trailer's own image is
        // unpredictable, and white type over a bright frame is unreadable.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              padding: EdgeInsets.fromLTRB(48 * scale, 36 * scale, 48 * scale, 48 * scale),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.78), Colors.transparent],
                ),
              ),
              child: entry == null ? const SizedBox.shrink() : _buildFacts(context, entry.item, scale),
            ),
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _buildControls(context, scale)),
      ],
    );
  }

  Widget _buildFacts(BuildContext context, MediaItem item, double scale) {
    final theme = Theme.of(context);
    final parts = <MetadataLinePart>[
      if (item.isMovie)
        MetadataLineText(t.discover.movie, dropPriority: 4)
      else if (item.isShow)
        MetadataLineText(t.discover.tvShow, dropPriority: 4),
      if (item.year != null) MetadataLineText(item.year.toString(), dropPriority: 0),
      if (mediaRatingsFor(item) case final ratings when ratings.isNotEmpty)
        MetadataLineRatings(ratings, dropPriority: 1),
      if (item.contentRating != null) MetadataLineText(formatContentRating(item.contentRating!), dropPriority: 2),
      // The genres are the reason this line exists on the stage: with several
      // chosen, knowing which one you are looking at is the whole point.
      if (item.genres case final genres? when genres.isNotEmpty)
        MetadataLineText(genres.take(3).join(', '), dropPriority: 3),
    ];
    final metadataSize = 20 * scale;
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: metadataSize,
      fontWeight: FontWeight.w700,
      letterSpacing: isOcker(context) ? metadataSize * 0.07 : 0.1,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.displaySmall?.copyWith(color: Colors.white, fontSize: 46 * scale, height: 1.05),
        ),
        SizedBox(height: 13 * scale),
        FittedMetadataLine(
          textStyle: monoFacts(context, textStyle),
          parts: parts,
          // Boxed in every theme — under "Glas" capsules of glass — like the
          // facts on the detail page and the spotlight.
          chipped: true,
          chipSpacing: 8 * scale,
          ratingIconSize: textStyle.fontSize,
          ratingSpacing: 4 * scale,
          ratingEntrySpacing: 12 * scale,
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context, double scale) {
    final entry = _current;
    return Container(
      padding: EdgeInsets.fromLTRB(48 * scale, 48 * scale, 48 * scale, 36 * scale),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.78), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          FocusableActionBar(
            spacing: 12 * scale,
            // BACK on a control leaves the stage, which is where BACK goes
            // everywhere else in the app. Nothing above these buttons wants
            // the focus, so UP stays with them.
            onBack: () => Navigator.of(context).maybePop(),
            actions: [
              _stageAction(
                icon: _isPlaying ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                label: _isPlaying ? t.common.pause : t.common.play,
                autofocus: true,
                onPressed: entry == null ? null : () => unawaited(_togglePause()),
              ),
              _stageAction(
                icon: Symbols.skip_next_rounded,
                label: t.trailerStage.nextTrailer,
                onPressed: _exhausted ? null : () => unawaited(_advance()),
              ),
              _stageAction(
                icon: Symbols.info_rounded,
                label: t.trailerStage.openDetail,
                onPressed: entry == null ? null : _openDetail,
              ),
              _stageAction(icon: Symbols.tune_rounded, label: t.trailerStage.chooseAgain, onPressed: _chooseAgain),
            ],
          ),
        ],
      ),
    );
  }

  /// What stands over the picture while there is no picture: the next title's
  /// own backdrop where there is one, and the report when the evening is over.
  Widget _buildCover(BuildContext context) {
    final theme = Theme.of(context);
    final entry = _current;
    final backdrop = entry?.item.backdropPaths?.firstOrNull ?? entry?.item.artPath;
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdrop != null && entry != null)
            Opacity(
              opacity: 0.35,
              child: OptimizedMediaImage(
                client: _clientFor(entry.item),
                imagePath: backdrop,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                imageType: ImageType.art,
              ),
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(64),
              child: _exhausted ? _buildExhausted(context) : const LoadingIndicatorBox(size: 44),
            ),
          ),
          if (!_exhausted && entry != null)
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Text(
                  entry.item.title ?? '',
                  style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The end of the evening, and the one honest number about it: how many
  /// titles were looked at, and how many of them had a trailer. A library
  /// whose films carry none says so here instead of showing an empty screen.
  Widget _buildExhausted(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _queue.found == 0 ? t.trailerStage.noTrailers : t.trailerStage.allSeen,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 12),
        Text(
          t.trailerStage.report(examined: _queue.examined, found: _queue.found),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 28),
        FocusableActionBar(
          actions: [
            _stageAction(
              icon: Symbols.tune_rounded,
              label: t.trailerStage.chooseAgain,
              autofocus: true,
              onPressed: _chooseAgain,
            ),
          ],
        ),
      ],
    );
  }
}

/// One control on the stage: an icon with its word, drawn as a pill that
/// fills white when the remote reaches it.
FocusableAction _stageAction({
  required IconData icon,
  required String label,
  VoidCallback? onPressed,
  bool autofocus = false,
}) => FocusableAction(
  debugLabel: 'trailer_stage_$label',
  autofocus: autofocus,
  onPressed: onPressed,
  builder: (context, state) {
    final enabled = onPressed != null;
    final tokens = Theme.of(context).extension<MonoTokens>();
    final background = state.showFocus ? Colors.white : Colors.white.withValues(alpha: 0.14);
    final foreground = state.showFocus ? Colors.black : Colors.white.withValues(alpha: enabled ? 0.92 : 0.4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(tokens?.radiusMd ?? 12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: foreground),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  },
);
