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

  /// "Flach" (Plebz): the day and the time are a pill at the head of the
  /// ruler, over the channel column, instead of a strip of their own above
  /// it — the design's place, and the strip's height goes to the rows. Glas
  /// too while [ockerFlatSizes] holds.
  bool get _timePillInRuler => _showsTimeNavigation && _ockerLayout && ockerFlatSizes(context);

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
  /// schedule for the picture. A phone or tablet: see [_handheldShowsPreview].
  bool get _showsPreview {
    if (PlatformDetector.isTV()) return true;
    if (PlatformDetector.isDesktopOS()) {
      final size = MediaQuery.sizeOf(context);
      return size.height >= 600 && size.width >= 900;
    }
    return _handheldShowsPreview;
  }

  /// Plebz: a phone held upright and a tablet either way up have the band too
  /// (the user's call, 2026-10-11): a tap puts a channel in it, a second tap,
  /// a tap on the picture or its button puts it on the whole screen. A phone on
  /// its side keeps the bare grid, whose tap goes straight to the whole screen —
  /// except while a channel plays in the band: turning the phone is then the
  /// way to the whole screen ([_followDeviceRotation]), and the band has to be
  /// there to hand the picture over.
  bool get _handheldShowsPreview {
    if (GuideTabState.debugHandheldPreview == false) return false;
    if (!GuidePreviewPlayerState.canPlayInline || !PlatformDetector.isMobile(context)) return false;
    final size = MediaQuery.sizeOf(context);
    if (size.shortestSide >= 600) return true;
    return size.height >= size.width || _previewChannel != null;
  }

  /// A phone held upright: the band is the picture across the whole width
  /// ([GuidePreviewBand]) rather than a picture beside its words.
  bool get _isPhoneBand {
    if (PlatformDetector.isTV() || !PlatformDetector.isMobile(context)) return false;
    final size = MediaQuery.sizeOf(context);
    return size.shortestSide < 600 && size.height >= size.width;
  }

  /// What is on the channel in the band.
  LiveTvProgram? get _previewProgram {
    final key = _previewChannel?.key;
    if (key == null) return null;
    final index = widget.channels.indexWhere((channel) => channel.key == key);
    return index < 0 ? null : _findCurrentProgram(index);
  }

  /// The band's button, or a tap on its picture: the second press.
  void _openPreviewFullScreen() {
    final channel = _previewChannel;
    if (channel != null) unawaited(_tuneOrPreview(channel));
  }

  /// Plebz: a phone turned on its side with a channel in the band takes it to
  /// the whole screen, and the player then follows the phone
  /// ([OrientationHelper.followDeviceRotation]); turned upright again, it
  /// gives the picture back to the band. Only on a turn, never on a state: a
  /// guide come back to on its side stays as it is.
  void _followDeviceRotation() {
    if (PlatformDetector.isTV() || !PlatformDetector.isMobile(context)) return;
    final size = MediaQuery.sizeOf(context);
    final orientation = size.width > size.height ? Orientation.landscape : Orientation.portrait;
    final previous = _lastOrientation;
    _lastOrientation = orientation;
    if (previous == null || previous == orientation || size.shortestSide >= 600) return;
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    if (orientation == Orientation.landscape) {
      final channel = _previewChannel;
      // A hidden tab keeps its guide mounted with its tickers off.
      if (channel == null || !onTop || !TickerMode.valuesOf(context).enabled) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _previewChannel?.key != channel.key) return;
        unawaited(_tuneOrPreview(channel, followDeviceRotation: true));
      });
    } else if (OrientationHelper.followDeviceRotation && !onTop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && OrientationHelper.followDeviceRotation) unawaited(Navigator.of(context).maybePop());
      });
    }
  }

  /// The guide is also built by hosts that have not loaded settings yet, and
  /// the strip has always been there — so an unread setting keeps it.
  bool get _showsTimeNavigation => SettingsService.instanceOrNull?.read(PlebzPrefs.liveTvGuideTimeNavigation) ?? true;

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
  /// Unless the playing picture itself can be handed over
  /// ([_handPictureToFullScreen]).
  Future<void> _tuneOrPreview(LiveTvChannel channel, {bool followDeviceRotation = false}) async {
    final play =
        widget.onPlayChannel ??
        (LiveTvChannel channel) => tuneChannel(channel, followDeviceRotation: followDeviceRotation);
    if (!_showsPreview) {
      await play(channel);
      return;
    }
    if (_previewChannel?.key != channel.key) {
      _setPreviewChannel(channel);
      return;
    }
    if (await _handPictureToFullScreen(channel, followDeviceRotation: followDeviceRotation)) return;
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

  /// The second press, with the picture already playing in the box: the
  /// full-screen player takes that very picture on and grows out of the box,
  /// so the channel never stops (Plebz, "Vorschau nahtlos ins Vollbild").
  /// False when it cannot — the switch is off, or the picture is not one that
  /// can move — and the ordinary way runs instead.
  Future<bool> _handPictureToFullScreen(LiveTvChannel channel, {bool followDeviceRotation = false}) async {
    if (widget.onPlayChannel != null) return false;
    final settings = SettingsService.instanceOrNull;
    if (settings == null || !LivePictureHandover.enabledIn(settings)) return false;
    final preview = _previewKey.currentState;
    final from = _previewRectInNavigator();
    if (preview == null || from == null) return false;
    final picture = preview.releaseForHandover();
    if (picture == null) return false;
    final opened = await tuneChannel(
      channel,
      handover: picture,
      pictureFrom: from,
      followDeviceRotation: followDeviceRotation,
    );
    if (!opened) {
      // Nothing took it on: the box plays on.
      final stillHere = mounted ? _previewKey.currentState : null;
      if (stillHere == null) {
        unawaited(picture.release());
      } else {
        stillHere.adopt(picture);
      }
    }
    return true;
  }

  /// Where the preview box sits, in the coordinates of the navigator the
  /// player is pushed onto — where the player grows from.
  Rect? _previewRectInNavigator() {
    final box = _previewKey.currentContext?.findRenderObject();
    final navigatorBox = Navigator.of(context).context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || navigatorBox is! RenderBox) return null;
    return box.localToGlobal(Offset.zero, ancestor: navigatorBox) & box.size;
  }

  /// The full-screen player giving its picture back on Back: the box takes it
  /// up and shows its channel, which is where the session ended up.
  void _takeReturnedPicture() {
    if (!mounted || !_showsPreview) return;
    final picture = LivePictureReturn.instance.take();
    if (picture == null) return;
    final preview = _previewKey.currentState;
    if (preview == null) {
      unawaited(picture.release());
      return;
    }
    preview.adopt(picture);
    _setPreviewChannel(picture.channel);
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
    final chrome = _timeHeaderHeight + (_showsTimeNavigation && !_timePillInRuler ? _timeNavigationHeight : 0.0);
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

  /// `‹ Heute ab 16:30 ›` under "Flach": one faint pill at the head of the
  /// ruler, each of its three parts focusable as the strip's were. Scaled
  /// down rather than cut where a long day name would not fit the column.
  Widget _buildFlatTimePill(String dayLabel, String timeLabel) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    final scale = ockerScale(context);
    final label = type.metadata.copyWith(fontSize: 17 * scale, fontWeight: .w500);

    Widget arrow({required int index, required IconData icon, required int hours}) => _timeNavFocusWrap(
      index: index,
      child: ClickableCursor(
        child: GestureDetector(
          onTap: () => _shiftTimeRange(hours),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 8 * scale),
            child: AppIcon(icon, size: 22 * scale, color: tk.ink(0.6)),
          ),
        ),
      ),
    );

    return Align(
      alignment: .centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: .centerLeft,
        child: Container(
          height: 44 * scale,
          padding: EdgeInsets.symmetric(horizontal: 6 * scale),
          decoration: ShapeDecoration(color: tk.ink(0.06), shape: const StadiumBorder()),
          child: Row(
            mainAxisSize: .min,
            children: [
              arrow(index: 0, icon: Symbols.chevron_left_rounded, hours: -2),
              _timeNavFocusWrap(
                index: 1,
                child: ClickableCursor(
                  child: GestureDetector(
                    key: _dayPickerKey,
                    onTap: _showDayPicker,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 8 * scale),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: dayLabel,
                              style: label.copyWith(color: tk.ink(1), fontWeight: .w600),
                            ),
                            TextSpan(
                              text: ' ${t.liveTv.fromTime(time: timeLabel)}',
                              style: label.copyWith(color: tk.ink(0.5)),
                            ),
                          ],
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              ),
              arrow(index: 2, icon: Symbols.chevron_right_rounded, hours: 2),
            ],
          ),
        ),
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

  /// The guide's body: under "Ocker" the preview band across the top, its
  /// picture top left and what is on beside it, the schedule across the full
  /// width under both; with a preview in the other themes the panel over the
  /// grid; without one the grid alone.
  Widget _buildGuideBody(ThemeData theme) {
    return _showsPreview && _ockerLayout
        // "Ocker" arranges Live TV the way every other variant does, and
        // the way this screen was always read: the picture top left, what
        // is on beside it, and the schedule across the full width under
        // both. It ran as a column down the left for a while; that gave
        // the grid its height back but took a quarter of its width, and a
        // guide with an hour and a half on screen is not a guide.
        ? Padding(
            // The same gap under the header every other screen keeps.
            // Without it the picture and the words began directly under
            // the row of destinations, which made the navigation look
            // like part of the panel.
            //
            // At the left it is the header's own inset, not the design's
            // safe margin: the destinations start there, and a schedule
            // stepping in another forty pixels past them read as a page
            // inside the page — the gap beside the first logo had no
            // job.
            padding: EdgeInsets.only(left: ockerFlushLeftInset(context), top: ockerContentTop(context)),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                // The band keeps a margin on the right — it is words, and
                // words want an edge to stop at. The schedule under it
                // does not: it runs off the screen because it carries on
                // past midnight, and a margin there would only mark where
                // it was cut.
                Padding(
                  padding: EdgeInsets.only(right: OckerLayout.safeMargin * ockerScale(context)),
                  child: ValueListenableBuilder<_GuideFocusSnapshot>(
                    valueListenable: _focusSnapshot,
                    builder: (context, focus, _) => OckerGuidePanel(
                      playerKey: _previewKey,
                      streamInfo: _previewStreamInfo,
                      previewChannel: _previewChannel,
                      focusedChannel: _channelAt(focus.channelIndex),
                      focusedProgram: focus.program ?? _findCurrentProgram(focus.channelIndex),
                      nextProgram: _findNextProgram(focus.channelIndex, focus.program),
                      sourceLabel: _channelAt(focus.channelIndex)?.serverName,
                    ),
                  ),
                ),
                SizedBox(height: 24 * ockerScale(context)),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _measureGridHeight(constraints.maxHeight);
                      return _buildGuideGrid(theme);
                    },
                  ),
                ),
              ],
            ),
          )
        : _showsPreview
        ? LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                if (_isPhoneBand)
                  SizedBox(
                    height: constraints.maxWidth * 9 / 16,
                    child: GuidePreviewBand(
                      playerKey: _previewKey,
                      previewChannel: _previewChannel,
                      program: _previewProgram,
                      onFullScreen: _openPreviewFullScreen,
                    ),
                  )
                else
                  SizedBox(
                    height: constraints.maxHeight * GuidePreviewPanel.heightFraction,
                    child: ValueListenableBuilder<_GuideFocusSnapshot>(
                      valueListenable: _focusSnapshot,
                      builder: (context, focus, _) => GuidePreviewPanel(
                        playerKey: _previewKey,
                        previewChannel: _previewChannel,
                        focusedChannel: _channelAt(focus.channelIndex),
                        focusedProgram: focus.program ?? _findCurrentProgram(focus.channelIndex),
                      ),
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _measureGridHeight(constraints.maxHeight);
                      return _buildGuideGrid(theme);
                    },
                  ),
                ),
              ],
            ),
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              _measureGridHeight(constraints.maxHeight);
              return _buildGuideGrid(theme);
            },
          );
  }

  /// Ocker's now-line: the accent, not a red that appears nowhere else —
  /// marking the present moment is one of the three jobs that colour has. The
  /// chip on top says which moment, because a line alone in a grid of
  /// half-hours is easy to read as a ruler tick.
  Widget _ockerNowLine(DateTime now, {required double left, required double gridHeight}) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    // A box of its own width, centred on the moment. The first cut hung an
    // OverflowBox off a Positioned with no width to work from, which is an
    // unbounded-width layout and draws nothing at all — the line simply was
    // not there under this theme.
    const chipBox = 96.0;
    return Positioned(
      left: left - chipBox / 2,
      top: 0,
      width: chipBox,
      height: gridHeight,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: .min,
          children: [
            // "Flach": level with the ruler's times rather than above them —
            // the pill is as tall as its figures and its padding.
            if (ockerFlatSizes(context))
              SizedBox(height: ((_timeHeaderHeight - 26 * ockerScale(context)) / 2).clamp(0.0, double.infinity)),
            if (ockerFlatSizes(context))
              // "Flach": a pill of the accent, its figures in whichever of white
              // or the ground reads on it — a picked yellow takes the dark.
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10 * ockerScale(context), vertical: 6 * ockerScale(context)),
                decoration: ShapeDecoration(color: tk.accent, shape: const StadiumBorder()),
                child: Text(
                  formatClockTime(now, is24Hour: MediaQuery.alwaysUse24HourFormatOf(context)),
                  style: type.nowChip.copyWith(
                    fontFamily: type.metadata.fontFamily,
                    fontSize: 14 * ockerScale(context),
                    fontWeight: .w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: ThemeData.estimateBrightnessForColor(tk.accent) == Brightness.dark ? Colors.white : tk.bg,
                  ),
                  maxLines: 1,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                color: tk.accent,
                child: Text(
                  formatClockTime(now, is24Hour: MediaQuery.alwaysUse24HourFormatOf(context)),
                  style: type.nowChip.copyWith(color: tk.bg),
                  maxLines: 1,
                ),
              ),
            Expanded(child: Container(width: 2, color: tk.accent)),
          ],
        ),
      ),
    );
  }

  /// An IPTV source has its own guide (XMLTV for a playlist, the panel's
  /// per-channel EPG for Xtream) and no DVR, so it adds programmes to
  /// [programs] but no scheduled recordings. False once a newer load has taken
  /// over, for the caller to stop there.
  Future<bool> _addIptvPrograms(
    List<IptvLiveTvSource> sources,
    List<LiveTvProgram> programs,
    DateTime from,
    DateTime to,
    int loadGeneration,
  ) async {
    for (final source in sources) {
      try {
        final fetched = await source.fetchSchedule(from: from, to: to);
        if (!_isCurrentProgramLoad(loadGeneration)) return false;
        programs.addAll(fetched);
      } catch (error, stackTrace) {
        if (!_isCurrentProgramLoad(loadGeneration)) return false;
        appLogger.e('Failed to load programs from an IPTV source', error: error, stackTrace: stackTrace);
      }
    }
    return true;
  }

  /// The channel asked for while the guide was loading ([showChannel]), put
  /// under the cursor now the programmes are in. Focus asked for meanwhile
  /// lands on that channel; an arrival's focusContent would put the cursor
  /// back on the first. False when no channel was waiting.
  bool _showPendingChannel({required bool shouldFocus, required int loadGeneration}) {
    final key = _pendingShowChannel;
    if (key == null) return false;
    _pendingShowChannel = null;
    showChannel(key);
    if (shouldFocus) {
      _pendingFocus = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isCurrentProgramLoad(loadGeneration)) resumeFocus();
      });
    }
    return true;
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
            // Under "Flach" the focused block inverts what it holds, so its
            // words stay dark on the white; the bar is a colour, not a word,
            // and keeps its accent (the user's call).
            child: OckerKeepColours(child: Container(height: 2, color: accent)),
          ),
        ),
      ],
    );
  }
}

/// What the Live TV screen asks of its guide (Plebz): take the cursor back,
/// show a channel, read the programmes again, go back to the top, stop the
/// preview.
extension GuideTabChannels on GuideTabState {
  /// Take the cursor back without moving it.
  ///
  /// For a host that borrowed focus for a moment — the column of groups off
  /// the left — and is handing it back. The grid remembers which channel it
  /// was on, so sending it to the top would lose the viewer's place for no
  /// reason; [focusContent] is for arriving, this is for returning.
  void resumeFocus() {
    if (!InputModeTracker.isKeyboardMode(context)) return;
    if (_isLoading) {
      _pendingFocus = true;
      return;
    }
    _guideFocusNode.requestFocus();
  }

  /// Bring [scopeKey]'s channel under the viewport and onto the cursor.
  ///
  /// What the guide is asked for after the player closes: the viewer left it
  /// on a channel, zapped away in full screen, and coming back to the row
  /// they started on would lose the journey they just made.
  ///
  /// A guide built just now keeps it until its programmes are in: the first
  /// load anchors the window on the live line, and the channel comes after.
  void showChannel(String scopeKey) {
    if (_isLoading) {
      _pendingShowChannel = scopeKey;
      return;
    }
    final index = widget.channels.indexWhere((channel) => liveTvChannelScopeKey(channel) == scopeKey);
    if (index < 0) {
      showFirstChannel();
      return;
    }
    // In the grid: the viewer left from a channel, and a guide built for a
    // hand-off would otherwise start out on the time bar.
    _updateFocus(() {
      _focusZone = _GuideZone.grid;
      _gridChannelIndex = index;
    });
    _scrollToChannel(index);
  }

  /// Ask every source for the programmes again — for channels shown again,
  /// whose IPTV guide was not read while they were hidden.
  void reloadPrograms() => unawaited(_loadPrograms());

  /// Put the top of the channel list back under the viewport.
  ///
  /// The grid keeps its scroll offset when the channel list is replaced, so
  /// switching group left the guide parked at the offset the previous group
  /// had been read at — with the first channel of the new one above the top
  /// edge, invisible until some later key press dragged it into view.
  void showFirstChannel() {
    if (_gridVerticalController.hasClients && _gridVerticalController.offset != 0) {
      _gridVerticalController.jumpTo(0);
    }
    if (_channelVerticalController.hasClients && _channelVerticalController.offset != 0) {
      _channelVerticalController.jumpTo(0);
    }
  }

  /// Give up the preview, if one is running.
  void stopPreview() {
    if (_previewChannel == null) return;
    _setPreviewChannel(null);
  }
}
