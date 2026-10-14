part of 'player_up_next_panel.dart';

/// The end card (Plebz, the user's design 2026-10-14): the whole screen at the
/// end of an episode, the playing episode shrunk into a box on the left and the
/// next one beside it — its still, series, title, facts and synopsis, and the
/// two ways on.
///
/// No overlay over the picture: the picture itself moves. [placePicture] is
/// told, frame by frame while the card opens and closes, where the playing
/// picture should be (logical pixels; null once it is back on the whole
/// screen), and the card paints its ground everywhere but there. Where the
/// player cannot move its picture ([movesPicture] false: a tunnelled surface,
/// a platform without the means) the box shows the episode's still instead,
/// while the sound plays on.
class PlayerEndCard extends StatefulWidget {
  const PlayerEndCard({
    super.key,
    required this.open,
    required this.current,
    required this.next,
    required this.movesPicture,
    required this.placePicture,
    required this.playLabel,
    required this.remaining,
    required this.playFocusNode,
    required this.creditsFocusNode,
    required this.onPlay,
    required this.onWatchCredits,
    required this.exitFocusNode,
    required this.onExit,
    this.suggestion = false,
  });

  final bool open;
  final MediaItem current;
  final MediaItem? next;
  final bool movesPicture;
  final void Function(Rect? picture) placePicture;

  /// The play button's words: the countdown while one runs.
  final ValueListenable<String> playLabel;

  /// What is left of the playing episode, under its box.
  final ValueListenable<Duration?> remaining;

  final FocusNode playFocusNode;
  final FocusNode creditsFocusNode;
  final VoidCallback onPlay;
  final VoidCallback onWatchCredits;

  /// [next] is a title like this one rather than its next episode: headed as
  /// a suggestion, its button opens its page, and nothing counts down.
  final bool suggestion;

  /// "Stop watching": leaves the player, nothing more starts.
  final FocusNode exitFocusNode;
  final VoidCallback onExit;

  /// How long the picture takes to shrink into its box or grow back.
  static const Duration motion = Duration(milliseconds: 320);

  /// Where the playing picture sits on a screen of [size].
  static Rect pictureBox(Size size) {
    final columns = _Columns(size);
    return Rect.fromLTWH(columns.left, columns.top, columns.width, columns.width * 9 / 16);
  }

  @override
  State<PlayerEndCard> createState() => _PlayerEndCardState();
}

/// The card's two columns on a screen: the same margins and gap as the design
/// (5 % of the width at the sides and between, the boxes below a heading).
class _Columns {
  _Columns(this.size);

  final Size size;

  double get margin => size.width * 0.05;
  double get gap => size.width * 0.05;
  double get width => (size.width - 2 * margin - gap) / 2;
  double get left => margin;
  double get right => margin + width + gap;
  double get headingTop => size.height * 0.07;
  double get top => size.height * 0.13;
}

class _PlayerEndCardState extends State<PlayerEndCard> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: PlayerEndCard.motion,
    value: widget.open ? 1 : 0,
  )..addListener(_onMotion);

  Size _size = Size.zero;

  double get _t => Curves.easeInOutCubic.transform(_motion.value);

  @override
  void didUpdateWidget(PlayerEndCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    if (widget.open) {
      unawaited(_motion.forward());
      // Focus on the play button once the card is up, on a remote.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.open) widget.playFocusNode.requestFocus();
      });
    } else {
      unawaited(_motion.reverse());
    }
  }

  void _onMotion() {
    if (!widget.movesPicture || _size.isEmpty) return;
    if (_motion.value == 0) {
      widget.placePicture(null);
    } else {
      widget.placePicture(Rect.lerp(Offset.zero & _size, PlayerEndCard.pictureBox(_size), _t));
    }
  }

  @override
  void dispose() {
    // Not placed back here: the card goes only with the player, whose picture
    // goes with it.
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _size = constraints.biggest;
      return AnimatedBuilder(
        animation: _motion,
        builder: (context, _) {
          if (_motion.value == 0) return const SizedBox.shrink();
          return _card(context, _t);
        },
      );
    },
  );

  Widget _card(BuildContext context, double p) {
    final tk = tokens(context);
    final ocker = isOcker(context);
    final columns = _Columns(_size);
    final box = PlayerEndCard.pictureBox(_size);
    final hole = Rect.lerp(Offset.zero & _size, box, p)!;
    final radius = Radius.circular(artworkRadius(context) * p);
    final ground = ocker ? tk.bg : Colors.black;
    final ink = ocker ? tk.ink(1) : Colors.white;
    final muted = ocker ? tk.ink(0.62) : Colors.white70;
    // Sized from the screen, as the design is: on a television's 960 logical
    // pixels the synopsis is about 13, the title 21.
    final unit = _size.width / 680;
    final eyebrow = TextStyle(fontSize: 8 * unit, letterSpacing: 1.4 * unit, fontWeight: FontWeight.w500, color: muted);
    final next = widget.next;

    return Stack(
      children: [
        // The ground everywhere but the picture's box: the picture behind
        // shows through it, and only there.
        Positioned.fill(
          child: IgnorePointer(
            child: widget.movesPicture
                ? CustomPaint(
                    painter: _GroundAround(hole: RRect.fromRectAndRadius(hole, radius), colour: ground),
                  )
                : Opacity(
                    opacity: p,
                    child: ColoredBox(color: ground),
                  ),
          ),
        ),
        // Where the picture cannot move: the episode's still in its box.
        if (!widget.movesPicture)
          Positioned.fromRect(
            rect: box,
            child: Opacity(
              opacity: p,
              child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(artworkRadius(context))),
                child: switch (widget.current.thumbPath) {
                  final thumb? => _episodeStill(context, widget.current, thumb),
                  null => ColoredBox(color: ink.withValues(alpha: 0.06)),
                },
              ),
            ),
          ),
        // Everything but the picture comes in as the picture makes room.
        Positioned.fill(
          child: Opacity(
            opacity: Curves.easeIn.transform(p),
            child: Stack(
              children: [
                Positioned(
                  left: columns.left,
                  top: columns.headingTop,
                  width: columns.width,
                  child: Text(t.videoControls.endCardNowPlaying, style: eyebrow, maxLines: 1, overflow: .ellipsis),
                ),
                Positioned(
                  left: columns.left,
                  top: box.bottom + 7 * unit,
                  width: columns.width,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          widget.current.title ?? widget.current.displayTitle,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: TextStyle(fontSize: 10 * unit, fontWeight: FontWeight.w500, color: ink),
                        ),
                      ),
                      ValueListenableBuilder<Duration?>(
                        valueListenable: widget.remaining,
                        builder: (context, left, _) => left == null
                            ? const SizedBox.shrink()
                            : Text(
                                t.videoControls.endCardRemaining(time: formatDurationTimestamp(left)),
                                style: TextStyle(fontSize: 9 * unit, color: muted),
                              ),
                      ),
                    ],
                  ),
                ),
                if (next != null) ...[
                  Positioned(
                    left: columns.right,
                    top: columns.headingTop,
                    width: columns.width,
                    child: Text(
                      !widget.suggestion
                          ? t.videoControls.upNext
                          : next.kind == MediaKind.show
                          ? t.videoControls.endCardSimilarShow
                          : t.videoControls.endCardSimilarMovie,
                      style: eyebrow,
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                  ),
                  Positioned(
                    left: columns.right,
                    top: columns.top,
                    width: columns.width,
                    bottom: _size.height * 0.04,
                    child: _NextColumn(
                      episode: next,
                      unit: unit,
                      ink: ink,
                      muted: muted,
                      playLabel: widget.playLabel,
                      playFocusNode: widget.playFocusNode,
                      creditsFocusNode: widget.creditsFocusNode,
                      onPlay: widget.onPlay,
                      onWatchCredits: widget.onWatchCredits,
                      exitFocusNode: widget.exitFocusNode,
                      onExit: widget.onExit,
                      suggestion: widget.suggestion,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The next episode: still, series, title, facts, synopsis and the buttons.
class _NextColumn extends StatelessWidget {
  const _NextColumn({
    required this.episode,
    required this.unit,
    required this.ink,
    required this.muted,
    required this.playLabel,
    required this.playFocusNode,
    required this.creditsFocusNode,
    required this.onPlay,
    required this.onWatchCredits,
    required this.exitFocusNode,
    required this.onExit,
    required this.suggestion,
  });

  final MediaItem episode;
  final double unit;
  final Color ink;
  final Color muted;
  final ValueListenable<String> playLabel;
  final FocusNode playFocusNode;
  final FocusNode creditsFocusNode;
  final VoidCallback onPlay;
  final VoidCallback onWatchCredits;
  final FocusNode exitFocusNode;
  final VoidCallback onExit;
  final bool suggestion;

  @override
  Widget build(BuildContext context) {
    // A suggested series or film names itself, not a series above it.
    final series = suggestion ? null : episode.grandparentTitle;
    final summary = episode.summary;
    final spoilersHidden =
        (SettingsService.instanceOrNull?.read(SettingsService.hideSpoilers) ?? false) && episode.shouldHideSpoiler;
    final facts = [
      if (episode.parentIndex case final season? when episode.index != null)
        t.videoControls.endCardSeasonEpisode(season: season, episode: episode.index!),
      if (episode.kind != MediaKind.show)
        if (episode.durationMs case final ms? when ms > 0) formatDurationTextual(ms),
      if (episode.year case final year?) '$year',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(artworkRadius(context))),
              border: Border.all(color: ink.withValues(alpha: 0.9), width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(artworkRadius(context))),
              child: switch (episode.thumbPath) {
                final thumb? => _episodeStill(context, episode, thumb),
                null => ColoredBox(color: ink.withValues(alpha: 0.06)),
              },
            ),
          ),
        ),
        SizedBox(height: 9 * unit),
        if (series != null && series.isNotEmpty)
          Text(
            series,
            maxLines: 1,
            overflow: .ellipsis,
            style: TextStyle(fontSize: 9.5 * unit, fontWeight: FontWeight.w500, color: muted),
          ),
        Text(
          episode.title ?? episode.displayTitle,
          maxLines: 2,
          overflow: .ellipsis,
          style: TextStyle(fontSize: 15 * unit, fontWeight: FontWeight.w600, height: 1.2, color: ink),
        ),
        if (facts.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 3 * unit),
            child: Text(
              facts,
              maxLines: 1,
              overflow: .ellipsis,
              style: TextStyle(fontSize: 8.5 * unit, color: muted),
            ),
          ),
        if (!spoilersHidden && summary != null && summary.trim().isNotEmpty)
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(top: 6 * unit),
              child: Text(
                summary.trim(),
                maxLines: 3,
                overflow: .ellipsis,
                style: TextStyle(fontSize: 9 * unit, height: 1.45, color: ink.withValues(alpha: 0.78)),
              ),
            ),
          ),
        SizedBox(height: 10 * unit),
        // Each button as wide as its words, the quieter two without a glyph;
        // a narrow card wraps them rather than cutting them short.
        Wrap(
          spacing: 8 * unit,
          runSpacing: 8 * unit,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: playLabel,
              builder: (context, label, _) => _UpNextButton(
                focusNode: playFocusNode,
                onPressed: onPlay,
                icon: suggestion ? Symbols.info_rounded : Symbols.play_arrow_rounded,
                label: label,
                offered: true,
                compact: true,
                onNavigateUp: () {},
                onNavigateDown: () {},
                onNavigateRight: () => creditsFocusNode.requestFocus(),
              ),
            ),
            _UpNextButton(
              focusNode: creditsFocusNode,
              onPressed: onWatchCredits,
              icon: null,
              label: t.videoControls.endCardWatchCredits,
              offered: false,
              compact: true,
              onNavigateUp: () {},
              onNavigateDown: () {},
              onNavigateLeft: () => playFocusNode.requestFocus(),
              onNavigateRight: () => exitFocusNode.requestFocus(),
            ),
            _UpNextButton(
              focusNode: exitFocusNode,
              onPressed: onExit,
              icon: null,
              label: t.videoControls.endCardExit,
              offered: false,
              compact: true,
              onNavigateUp: () {},
              onNavigateDown: () {},
              onNavigateLeft: () => creditsFocusNode.requestFocus(),
            ),
          ],
        ),
      ],
    );
  }
}

/// The card's ground with a rounded hole where the picture is.
class _GroundAround extends CustomPainter {
  const _GroundAround({required this.hole, required this.colour});

  final RRect hole;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(hole);
    canvas.drawPath(path, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_GroundAround oldDelegate) => oldDelegate.hole != hole || oldDelegate.colour != colour;
}
