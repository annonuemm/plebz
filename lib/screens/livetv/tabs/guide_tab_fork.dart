part of 'guide_tab.dart';

// Plebz's own share of the guide: the timeline and day-picker helpers, the
// preview band's channel, pointer and remote handling that tunes or previews,
// the way home through the grid, and the redesign's time navigation. Kept out
// of upstream's file so a merge meets its own code there and ours here; the
// state's fields, the overrides and what other files call stay in the class.

/// One channel's programmes as a single line through time, the way the grid
/// draws them.
///
/// Guides overlap. An entry runs past the start of the next (a match listed
/// until 14:56 when the next begins at 14:50), or two guides both describe
/// the channel. Laid out as they came, the cells lay on top of each other and
/// their titles printed over each other — both pinned at the grid's left edge
/// when they had begun before it. So an entry ends where the next begins, and
/// one that begins in the same second as an earlier one is dropped: the
/// earlier keeps its slot. Everything that reads the index — the cells, the
/// "now" line, "Danach", D-pad — then sees the same timeline.
@visibleForTesting
List<LiveTvProgram> guideTimeline(List<LiveTvProgram> programs) {
  final ordered = programs.indexed.toList()
    ..sort((a, b) {
      final byStart = (a.$2.beginsAt ?? 0).compareTo(b.$2.beginsAt ?? 0);
      // Stable: of two with the same start, the one that came first stays.
      return byStart != 0 ? byStart : a.$1.compareTo(b.$1);
    });
  final timeline = <LiveTvProgram>[];
  for (final (_, program) in ordered) {
    final previous = timeline.lastOrNull;
    final begins = program.beginsAt;
    final previousBegins = previous?.beginsAt;
    if (previous != null && begins != null && previousBegins != null) {
      if (begins == previousBegins) continue;
      final previousEnds = previous.endsAt;
      if (previousEnds != null && previousEnds > begins) {
        timeline[timeline.length - 1] = previous.copyWith(endsAt: begins);
      }
    }
    timeline.add(program);
  }
  return timeline;
}

/// The days the guide's day picker offers: as far back as an archive reaches,
/// today, and ahead only the days a guide has programmes for — a day on which
/// no programme begins would open an empty grid. [lastProgrammeStart] null
/// means the reach is not known (a server's guide, asked window by window),
/// and then the whole [maxAhead] is offered as before.
@visibleForTesting
List<DateTime> guidePickerDays(
  DateTime today, {
  required int archiveDays,
  required DateTime? lastProgrammeStart,
  int maxAhead = 7,
}) => [
  for (var i = archiveDays; i > 0; i--) DateTime(today.year, today.month, today.day - i),
  today,
  for (var i = 1; i <= maxAhead; i++)
    if (lastProgrammeStart == null || !lastProgrammeStart.isBefore(DateTime(today.year, today.month, today.day + i)))
      DateTime(today.year, today.month, today.day + i),
];

extension _GuideTabFork on GuideTabState {
  /// What the time-shift strip above the grid takes: an IconButton at compact
  /// density plus the padding around it. Under "Ocker" the strip is a short
  /// centred cluster rather than a full-width bar, so it needs less.
  double get _timeNavigationHeight => _ockerLayout ? 32.0 : 44.0;

  /// Whether the band above the grid — the live picture, the title of what is
  /// on, and its description — is drawn at all.
  ///
  /// The rule the band was always meant to follow is *room*, not television:
  /// it costs [GuidePreviewPanel.heightFraction] of the guide's height, and
  /// that only pays for itself where the rest still shows a schedule. It was
  /// written as `isTV()`, which left every desktop window with a bare grid and
  /// no title or description anywhere — while the players on those hosts had
  /// been able to place an inline picture all along
  /// ([GuidePreviewPlayer.canPlayInline]).
  ///
  /// So a desktop window gets it too, once it is big enough to keep a guide
  /// under it: below roughly this height the seven-tenths left over is the
  /// eight rows at their floor, and a shorter window would be trading the
  /// schedule for the picture. A phone or tablet keeps the bare grid.
  bool get _showsPreview {
    if (PlatformDetector.isTV()) return true;
    if (!PlatformDetector.isDesktopOS()) return false;
    final size = MediaQuery.sizeOf(context);
    return size.height >= 600 && size.width >= 900;
  }

  /// The guide is also built by hosts that have not loaded settings yet, and
  /// the strip has always been there — so an unread setting keeps it.
  bool get _showsTimeNavigation =>
      SettingsService.instanceOrNull?.read(SettingsService.liveTvGuideTimeNavigation) ?? true;

  /// What the last preview said about its stream belongs to that stream, so
  /// it goes with it; the new one reports its own once it plays.
  void _setPreviewChannel(LiveTvChannel? channel) {
    _previewStreamInfo.value = null;
    _setState(() => _previewChannel = channel);
  }

  /// Focus tracking compares by identity, so a reload orphans the focused
  /// program — the fresh list's objects, or the new copy of an entry the
  /// timeline shortened (see [guideTimeline]). Re-resolve it against the
  /// index: the same object, else the same slot, else what is on now.
  void _reresolveFocusedProgram() {
    final focused = _focusedProgram;
    if (_focusZone != _GuideZone.grid || _gridColumn != 1 || focused == null) return;
    if (_gridChannelIndex < 0 || _gridChannelIndex >= widget.channels.length) return;
    final programs = _getProgramsForChannel(widget.channels[_gridChannelIndex]);
    if (programs.any((p) => identical(p, focused))) return;
    _focusedProgram =
        programs.where((p) => p.beginsAt == focused.beginsAt).firstOrNull ?? _findCurrentProgram(_gridChannelIndex);
  }

  /// A click is also a way of pointing at something.
  ///
  /// The D-pad moves the guide's cursor and *then* acts on what it stands on,
  /// so the band above the grid — the title, the description — follows by
  /// itself. A pointer skipped that entirely: the blocks do not take focus
  /// (`canRequestFocus: false`, so a click cannot strand the keyboard cursor
  /// inside the grid), and the band went on describing whatever the cursor had
  /// been left on. So a click moves the cursor first, exactly as a press
  /// would, and then does the same thing a press does.
  void _activateProgramFromPointer(LiveTvChannel channel, LiveTvProgram program) {
    final index = _channelIndexFor(channel);
    if (index != null) {
      _updateFocus(() {
        _focusZone = _GuideZone.grid;
        _gridChannelIndex = index;
        _gridColumn = 1;
        _focusedProgram = program;
      });
    }
    _activateProgram(channel, program);
  }

  /// The same for the logo column, where the cursor lands on the channel
  /// rather than on one of its programmes.
  void _tuneOrPreviewFromPointer(LiveTvChannel channel) {
    final index = _channelIndexFor(channel);
    if (index != null) {
      _updateFocus(() {
        _focusZone = _GuideZone.grid;
        _gridChannelIndex = index;
        _gridColumn = 0;
        _focusedProgram = null;
      });
    }
    unawaited(_tuneOrPreview(channel));
  }

  /// First press puts the channel in the preview window, second press puts it
  /// on the whole screen.
  ///
  /// The two cannot overlap: there is one native player core, so the preview
  /// is released before the full-screen player is opened. That costs the
  /// picture a moment while it is rebuilt — the alternative is two cores,
  /// which is a native change out of proportion to a preview window.
  Future<void> _tuneOrPreview(LiveTvChannel channel) async {
    final play = widget.onPlayChannel ?? tuneChannel;
    if (!_showsPreview) {
      await play(channel);
      return;
    }
    if (_previewChannel?.key != channel.key) {
      _setPreviewChannel(channel);
      return;
    }
    await _previewKey.currentState?.stopForHandover();
    if (!mounted) return;
    _setPreviewChannel(null);
    await play(channel);
    // Back from the player, the picture the viewer left goes back in the box.
    // Only here: a guide left by any other route stops the preview and means
    // it (see [onRefreshPaused]).
    if (!mounted) return;
    _setPreviewChannel(channel);
  }

  LiveTvChannel? _channelAt(int index) => index >= 0 && index < widget.channels.length ? widget.channels[index] : null;

  /// Where UP off the top row goes.
  ///
  /// The time strip when it is shown, and past it when it is not: an invisible
  /// stop costs a press and gives nothing back — the cursor simply seems to
  /// vanish for a beat somewhere above the grid.
  void _exitGridUpwards() {
    if (_showsTimeNavigation) {
      _updateFocus(() {
        _focusZone = _GuideZone.timeNav;
        _timeNavIndex = 1;
      });
      return;
    }
    widget.onNavigateUp?.call();
  }

  /// The channel the guide comes home to: the one in the preview window, else
  /// the one last watched full screen, else the first.
  int? _homeChannelIndex() {
    if (widget.channels.isEmpty) return null;
    for (final key in [
      if (_previewChannel case final preview?) liveTvChannelScopeKey(preview),
      ?LiveTvLastSelection.instance.channelKey,
    ]) {
      final index = widget.channels.indexWhere((channel) => liveTvChannelScopeKey(channel) == key);
      if (index >= 0) return index;
    }
    return 0;
  }

  /// BACK from somewhere in the grid: the cursor goes home — onto the logo
  /// of the channel on show (see [_homeChannelIndex]), at the far left, with
  /// the window back on the live line. The logo rather than the programme:
  /// it is where a walk through the guide starts. False when
  /// it is there already, which is when BACK leaves the grid.
  bool _returnHome() {
    final home = _homeChannelIndex();
    if (home == null) return false;
    final live = _nowInWindow(DateTime.now());
    if (live && _gridChannelIndex == home && _gridColumn == 0) return false;

    _updateFocus(() {
      _gridChannelIndex = home;
      _gridColumn = 0;
      _focusedProgram = null;
    });
    _scrollToChannel(home);
    if (live) {
      _scrollToNow();
    } else {
      _jumpToNow();
    }
    return true;
  }

  /// What follows [after] on the same channel — the panel's "Danach 19:15 · …".
  ///
  /// A guide is read to answer two questions at once: what is on, and what is
  /// on next. The grid answers the second by being a grid; the panel has to
  /// say it.
  LiveTvProgram? _findNextProgram(int channelIndex, LiveTvProgram? after) {
    if (channelIndex < 0 || channelIndex >= widget.channels.length) return null;
    final reference = after ?? _findCurrentProgram(channelIndex);
    final start = reference?.endsAt;
    if (start == null) return null;
    final programs = _getProgramsForChannel(widget.channels[channelIndex]);
    for (final program in programs) {
      if ((program.beginsAt ?? 0) >= start) return program;
    }
    return null;
  }

  /// What is left for the rows once the time ruler and the navigation strip
  /// above them have had theirs.
  void _measureGridHeight(double maxHeight) {
    final chrome = _timeHeaderHeight + (_showsTimeNavigation ? _timeNavigationHeight : 0.0);
    final rows = maxHeight - chrome;
    if (rows.isFinite && rows > 0) _gridHeight = rows;
  }

  /// How far ahead the guides reach, by their last programme's start — known
  /// only when every guide here is an IPTV one, whose guide is read whole. A
  /// server (Plex, Jellyfin) is asked window by window and usually reaches a
  /// fortnight, so with one in the guide the reach counts as unknown (null).
  DateTime? _lastProgrammeStart() {
    if (context.read<MultiServerProvider>().liveTvServers.isNotEmpty) return null;
    final sources = context.read<IptvSourcesProvider?>()?.liveTvSources ?? const <IptvLiveTvSource>[];
    int? last;
    for (final source in sources) {
      final begins = source.lastProgrammeStart;
      if (begins != null && (last == null || begins > last)) last = begins;
    }
    // No guide loaded at all: nothing ahead to offer, today stays.
    return last == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(last * 1000);
  }

  /// `‹ Heute ⌄ 11:30 ›` — one short cluster in the middle of the guide.
  ///
  /// The bar this replaces pushed its two arrows to the far ends of the
  /// screen, which made a control that adjusts one number as wide as the
  /// schedule it adjusts: a metre of empty band between the left arrow and
  /// what it shifts. Beside the words they act on, they are read as belonging
  /// to them, and the height they give back goes to the channels.
  Widget _buildOckerTimeNavigation(String dayLabel, String timeLabel) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    final scale = ockerScale(context);

    Widget arrow({required int index, required IconData icon, required int hours}) => _timeNavFocusWrap(
      index: index,
      child: ClickableCursor(
        child: GestureDetector(
          onTap: () => _shiftTimeRange(hours),
          child: Padding(
            padding: EdgeInsets.all(4 * scale),
            child: AppIcon(icon, size: 18 * scale, color: tk.ink(0.72)),
          ),
        ),
      ),
    );

    return SizedBox(
      height: _timeNavigationHeight,
      child: Row(
        mainAxisAlignment: .center,
        children: [
          arrow(index: 0, icon: Symbols.chevron_left_rounded, hours: -2),
          SizedBox(width: 12 * scale),
          _timeNavFocusWrap(
            index: 1,
            child: ClickableCursor(
              child: GestureDetector(
                key: _dayPickerKey,
                onTap: _showDayPicker,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 3 * scale),
                  child: Row(
                    mainAxisSize: .min,
                    children: [
                      Text(dayLabel, style: type.metadata.copyWith(color: tk.ink(1))),
                      SizedBox(width: 3 * scale),
                      AppIcon(Symbols.keyboard_arrow_down_rounded, size: 15 * scale, color: tk.ink(0.6)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 12 * scale),
          // Mono, like every other time in this design.
          Text(timeLabel, style: type.counter.copyWith(color: tk.ink(0.72))),
          SizedBox(width: 12 * scale),
          arrow(index: 2, icon: Symbols.chevron_right_rounded, hours: 2),
        ],
      ),
    );
  }

  /// When a programme starts and how long it runs, inside its own block.
  ///
  /// Mono and regular where the title above it is the interface face at 600.
  /// Three lines all set in one voice made a block a paragraph to read rather
  /// than a title with two facts under it; the change of family does most of
  /// the separating here, and the weight the rest. The style itself was
  /// written for exactly this and had never been wired up.
  ///
  /// The colour is the subtitle's own, stepped down rather than replaced: a
  /// block that has already aired is dimmer to start with, and a fixed value
  /// here would make its times brighter than its title.
  TextStyle _ockerTimecodeStyle(BuildContext context, Color subtitleColor) =>
      OckerType.of(context).timecode.copyWith(color: subtitleColor.withValues(alpha: subtitleColor.a * 0.82));

  /// How much of [program] has already gone out, 0..1.
  double _airedFraction(LiveTvProgram program) {
    final start = program.beginsAt;
    final end = program.endsAt;
    if (start == null || end == null || end <= start) return 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return ((now - start) / (end - start)).clamp(0.0, 1.0);
  }
}

/// A programme block's contents, with the aired-so-far bar along its foot.
///
/// The bar belongs in here rather than on top of the block from outside: laid
/// over it, it ran straight past the block's rounded corners and hung out under
/// them — which, on the one block that has a ring round it, read as the focused
/// programme being a different size from every other in its row.
class _ProgramBlockBody extends StatelessWidget {
  final Widget child;

  /// How much of the programme has gone out, or null where that is not a
  /// question about it — a repeat from this morning, a film at nine.
  final double? progress;

  final Color accent;

  const _ProgramBlockBody({required this.child, required this.progress, required this.accent});

  @override
  Widget build(BuildContext context) {
    final fraction = progress;
    if (fraction == null) return child;
    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: FractionallySizedBox(
            alignment: .centerLeft,
            widthFactor: fraction,
            child: Container(height: 2, color: accent),
          ),
        ),
      ],
    );
  }
}
