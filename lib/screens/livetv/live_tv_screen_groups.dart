part of 'live_tv_screen.dart';

// Plebz's own share of the Live TV screen: the channel groups and their
// column, the channel arrangement, the hand-off from the player, the redesign's
// rail menu and the channel and group menus. Kept out of upstream's file so an
// upstream merge meets its own code there and ours here; the state's fields
// and the overrides stay in the class, as an extension can hold neither.

extension _LiveTvScreenFork on _LiveTvScreenState {
  /// Channels in the selected group, in channel order. The favorites filter
  /// applies on top of this, so a group selection narrows both.
  List<LiveTvChannel> get _groupedChannels {
    final group = _selectedGroup;
    if (group == null) return _channels;
    return [
      for (final channel in _channels)
        if (liveTvNonEmpty(channel.lineup) == group) channel,
    ];
  }

  /// Group labels in the arranged order, with their channel counts. Built
  /// from the visible channels, so a hidden group is simply not offered.
  List<ChannelGroupOption> get _channelGroupOptions {
    final counts = <String, int>{};
    for (final channel in _channels) {
      final group = liveTvNonEmpty(channel.lineup);
      if (group == null) continue;
      counts[group] = (counts[group] ?? 0) + 1;
    }
    return [
      (key: null, label: t.liveTv.allChannels, count: _channels.length),
      for (final entry in counts.entries) (key: entry.key, label: _groupLabel(entry.key), count: entry.value),
    ];
  }

  /// Whether a provider's country prefix is left off the chips. Read on every
  /// build and watched below, so switching it takes effect without a reload.
  bool get _hideGroupCountryPrefix =>
      SettingsService.instanceOrNull?.read(SettingsService.iptvHideGroupCountryPrefix) ?? false;

  /// What a group is called on screen: the name the user gave it, else the
  /// provider's own, with or without its country prefix.
  String _groupLabel(String groupKey) => liveTvGroupLabel(
    groupKey,
    stripCountryPrefix: _hideGroupCountryPrefix,
    customName: _layoutProvider?.layout.groupNames[groupKey],
  );

  /// True once the loaded channels carry more than one group — a single group
  /// (or none, which is what Plex and Jellyfin lineups look like) is nothing
  /// to choose between.
  bool get _hasChannelGroups => _channelGroupOptions.length > 2;

  /// Whether the groups are chosen in a column off the left of the guide,
  /// TiviMate-style — wherever there are groups to choose between.
  ///
  /// It was a setting, beside a bar of group chips above the guide and, in the
  /// redesign, a list behind "Live-TV". The column is the one way now: the
  /// bar is gone in every theme, and the redesign's menu behind "Live-TV"
  /// holds the page's views instead ([ockerRailMenu]).
  bool get _groupColumnEnabled => _hasChannelGroups;

  /// Whether the column simply stands there instead of coming and going.
  ///
  /// The drawer exists because a television screen has no room to spare and a
  /// remote has no way to point at something parked at the edge. A Mac has
  /// both: a window wide enough to keep the list in view, and a pointer for
  /// which a panel that folds away the moment focus leaves it is a panel that
  /// keeps disappearing mid-click. So on macOS the column stands
  /// open, not as a drawer.
  bool get _groupColumnPinned => _groupColumnEnabled && Platform.isMacOS;

  /// Whether that column is showing. It takes its width from the layout rather
  /// than floating over it, so opening it pushes the guide, the picture and
  /// the description to the right — which is the whole point: nothing is
  /// covered while the choice is made.
  bool get _groupColumnOpen => _groupColumnPinned || _groupColumnDrawerOpen;

  /// Close as soon as the cursor is not in the column any more.
  ///
  /// Both ways out are the same thing to the viewer: choosing a group, or
  /// stepping off the list at its top or bottom. What must not happen is the
  /// column staying open behind a cursor that has gone back to the guide —
  /// that is a drawer left hanging and a focus ring nowhere near it.
  void _onGroupColumnFocusChange(bool hasFocus) {
    if (hasFocus) {
      _groupColumnHadFocus = true;
      return;
    }
    if (!_groupColumnHadFocus || !_groupColumnOpen) return;
    _groupColumnHadFocus = false;
    // No focus to return: it has already gone wherever it went.
    _closeGroupColumn(returnFocus: false);
  }

  void _openGroupColumn() {
    if (!_groupColumnEnabled) return;
    // Nothing to open where it never closed — LEFT just moves the cursor into
    // the list that is already standing there.
    if (_groupColumnPinned) {
      _focusGroupColumn(attempt: 0);
      return;
    }
    if (_groupColumnOpen) return;
    _groupColumnHadFocus = false;
    // The list is put where the cursor will leave it *before* it opens, so it
    // opens standing still on the group in force — not at its old place, then
    // jumping, then gliding the last stretch as focus centred the row.
    _settleGroupColumnOn(_selectedGroup);
    _setState(() => _groupColumnDrawerOpen = true);
    // After the frame that gives the column its width: a node inside a box of
    // zero width has nothing to focus.
    _focusGroupColumn(attempt: 0);
  }

  /// Put the cursor on the group that is on, or on the first one.
  ///
  /// Two things can be untrue on the frame after opening: the column may not
  /// have its width yet, and the row for the chosen group may not be built —
  /// a list builds what it can see. Both resolve within a frame or two, so
  /// this tries again rather than leaving the column open and unfocused,
  /// which is what it did in the themes whose grid takes a frame longer.
  void _focusGroupColumn({required int attempt}) {
    // A frame of its own: where the column stands open already nothing else
    // asks for one, and the cursor waited for whatever repainted next.
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_groupColumnOpen) return;
      // First bring the chosen group into view. The list keeps its place
      // while shut, and that place may be anywhere: the row may not be built,
      // or — once it held focus — be kept alive out of sight, where focusing
      // it came to nothing and the column stood open with no row to be on.
      if (attempt < 2 && _settleGroupColumnOn(_selectedGroup)) {
        _focusGroupColumn(attempt: attempt + 1);
        return;
      }
      final node = _groupChipFocusNode(_selectedGroup);
      if (node.context != null) {
        node.requestFocus();
        return;
      }
      // The top of the list is always there, and it is "all channels".
      final first = _groupChipFocusNode(_channelGroupOptions.first.key);
      if (first.context != null) {
        first.requestFocus();
        return;
      }
      if (attempt < 3) _focusGroupColumn(attempt: attempt + 1);
    });
  }

  /// Jumps the column's list to where focusing [group]'s row will leave it —
  /// the row in the middle, as a focused row always is — so that focusing it
  /// moves nothing. True when it had to move.
  bool _settleGroupColumnOn(String? group) {
    if (!_groupColumnScroll.hasClients) return false;
    final position = _groupColumnScroll.position;
    final target = _groupRowCentredOffset(group, position.viewportDimension).clamp(0.0, position.maxScrollExtent);
    if ((target - position.pixels).abs() <= 1) return false;
    _groupColumnScroll.jumpTo(target);
    return true;
  }

  /// [group]'s row where it is built and in the tree — a node keeps the
  /// context of a row the list has since let go of.
  RenderBox? _groupRowBox(String? group) {
    final context = _groupChipFocusNode(group).context;
    if (context == null || !context.mounted) return null;
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  /// The scroll offset that puts [group]'s row in the middle of the list.
  /// Exact where the row is built; otherwise worked out from a row that is —
  /// rows are one height, a title and a count.
  double _groupRowCentredOffset(String? group, double viewport) {
    final row = _groupRowBox(group);
    if (row != null) {
      final reveal = RenderAbstractViewport.maybeOf(row)?.getOffsetToReveal(row, 0.5);
      if (reveal != null) return reveal.offset;
    }
    final options = _channelGroupOptions;
    final index = options.indexWhere((option) => option.key == group);
    if (index <= 0) return 0;
    final built = [
      for (var i = 0; i < options.length; i++)
        if (_groupRowBox(options[i].key) case final box?) (i, box),
    ];
    if (built.length < 2) {
      final rowHeight = built.firstOrNull?.$2.size.height ?? 0;
      return index * rowHeight - (viewport - rowHeight) / 2;
    }
    // The pitch between two built rows — the row and whatever pads it.
    final (firstIndex, first) = built.first;
    final (lastIndex, last) = built.last;
    final pitch = (last.localToGlobal(Offset.zero).dy - first.localToGlobal(Offset.zero).dy) / (lastIndex - firstIndex);
    final firstReveal = RenderAbstractViewport.maybeOf(first)?.getOffsetToReveal(first, 0.5).offset;
    if (firstReveal == null) return index * pitch - (viewport - first.size.height) / 2;
    return firstReveal + (index - firstIndex) * pitch;
  }

  /// Leave the column for the navigation — the rail beside it, or the header
  /// band above it, whichever this theme has.
  void _leaveGroupColumnForNavigation() {
    _closeGroupColumn(returnFocus: false);
    MainScreenFocusScope.focusSidebarOf(context);
  }

  /// Close it and put the cursor back where it came from — the channel the
  /// viewer was standing on.
  /// [resumeWhereItWas] hands the cursor back to the channel the viewer was
  /// standing on, which is right for a column dismissed without a choice.
  /// Choosing a group changes the list under it, so that case starts at the
  /// top instead.
  void _closeGroupColumn({bool returnFocus = true, bool resumeWhereItWas = false}) {
    if (!_groupColumnOpen) return;
    _groupColumnHadFocus = false;
    // A pinned column keeps its place; only the cursor goes back. Which also
    // makes the "focus left the column" rule a no-op there, as it should be:
    // focus leaving a panel that never hides is just focus leaving.
    if (!_groupColumnPinned) _setState(() => _groupColumnDrawerOpen = false);
    if (!returnFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final guide = resumeWhereItWas ? _guideTabKey.currentState : null;
      if (guide != null) {
        guide.resumeFocus();
        return;
      }
      _focusCurrentTab();
    });
  }

  /// What the player is handed: everything this screen *could* show, with the
  /// group filter left off.
  ///
  /// The player builds its own group list out of what it is given, so handing
  /// it the narrowed list left it with one group and nothing for RIGHT to
  /// open. It narrows by group itself instead — the selected group travels
  /// beside this as a state. Favourites stay applied here, because the player
  /// has no notion of them and could not put one back.
  List<LiveTvChannel> get _playerChannels => filterLiveTvChannelsForFavorites(
    channels: _channels,
    favoritesOnly: _showFavoritesOnly,
    favoritesLoaded: _favoritesLoaded,
    favorites: _favoriteChannels,
    sourceForChannel: _sourceForChannel,
  );

  /// For a guide built after the request — the view switched to for a
  /// hand-off: it keeps the channel until its programmes are in.
  String? _takePendingChannel() {
    final key = _pendingChannelKey;
    _pendingChannelKey = null;
    return key;
  }

  void _showPendingChannel() {
    final key = _pendingChannelKey;
    if (key == null || !_channels.any((channel) => liveTvChannelScopeKey(channel) == key)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final guide = _guideTabKey.currentState;
      if (!mounted || guide == null || _pendingChannelKey != key) return;
      _pendingChannelKey = null;
      guide.showChannel(key);
    });
  }

  void _applyChannelLayout() {
    if (!mounted) return;
    final layout = _layoutProvider?.layout ?? LiveTvChannelLayout.empty;
    final channels = applyLiveTvChannelLayout(_loadedChannels, layout);
    _setState(() {
      _channels = channels;
      // A group that was hidden or that the reload no longer carries would
      // filter the guide down to nothing with no way back except the sheet.
      if (_selectedGroup != null && !channels.any((c) => liveTvNonEmpty(c.lineup) == _selectedGroup)) {
        _selectedGroup = null;
      }
    });
    // A channel handed over before the list was there is shown once it is.
    _showPendingChannel();
  }

  FocusNode _groupChipFocusNode(String? group) =>
      _groupChipFocusNodes.putIfAbsent(group ?? '', () => FocusNode(debugLabel: 'group_chip_${group ?? 'all'}'));

  void _notifySidebar() => _sidebarRevision.value++;

  /// The menu's own values for its actions; views are their index.
  static const _manageChannelsEntry = -1;

  static const _favoritesEntry = -2;

  static const _reorderFavoritesEntry = -3;

  static const _reloadEntry = -4;

  List<AppMenuEntry<int>> _ockerMenuEntries() {
    final views = _visibleTabs.length > 1;
    final recordings = _currentTab == LiveTvTab.recordings;
    return [
      if (views) ...[
        for (var i = 0; i < _visibleTabs.length; i++)
          AppMenuItem<int>(value: i, label: _getTabLabel(_visibleTabs[i]), selected: i == tabController.index),
        const AppMenuDivider<int>(),
      ],
      if (canManageChannels)
        AppMenuItem<int>(value: _manageChannelsEntry, icon: Symbols.tune_rounded, label: t.liveTv.manageChannels),
      if (!recordings) ...[
        AppMenuItem<int>(
          value: _favoritesEntry,
          icon: _showFavoritesOnly ? Symbols.star_rounded : Symbols.star_outline_rounded,
          label: t.liveTv.favorites,
          selected: _showFavoritesOnly,
        ),
        if (canReorderFavorites)
          AppMenuItem<int>(
            value: _reorderFavoritesEntry,
            icon: Symbols.swap_vert_rounded,
            label: t.liveTv.reorderFavorites,
          ),
      ],
      AppMenuItem<int>(
        value: _reloadEntry,
        icon: Symbols.refresh_rounded,
        label: recordings ? t.common.refresh : t.liveTv.reloadGuide,
      ),
    ];
  }

  void _onOckerMenuChosen(int chosen) {
    switch (chosen) {
      case _manageChannelsEntry:
        _showChannelManagement();
      case _favoritesEntry:
        _toggleFavoritesFilter();
      case _reorderFavoritesEntry:
        _showReorderFavorites();
      case _reloadEntry:
        manualRefresh();
      default:
        _setState(() => tabController.index = chosen);
        _focusViewOnceBuilt(chosen);
    }
  }

  /// Focus [index]'s content once its page is there: the views slide across
  /// over several frames, and a request made before the page exists goes
  /// nowhere.
  void _focusViewOnceBuilt(int index, {int framesLeft = 40}) {
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || tabController.index != index) return;
      final built = switch (_visibleTabs[index]) {
        LiveTvTab.guide => _guideTabKey.currentState != null || _guideShowsFavoritesEmptyState,
        LiveTvTab.whatsOn => _whatsOnTabKey.currentState != null,
        LiveTvTab.recordings => _recordingsTabKey.currentState != null,
      };
      if (built) {
        _focusCurrentTab();
      } else if (framesLeft > 0) {
        _focusViewOnceBuilt(index, framesLeft: framesLeft - 1);
      }
    });
  }

  void _showChannelManagement() {
    unawaited(showChannelManagementSheet(context, channels: _loadedChannels));
  }

  void _selectGroup(String? group) {
    if (group == _selectedGroup) return;
    _setState(() => _selectedGroup = group);
    // The guide keeps its scroll offset across a channel-list change, so show
    // the new group from its first channel and hand focus back to the content
    // that just replaced it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _guideTabKey.currentState?.showFirstChannel();
      _focusCurrentTab();
    });
  }

  /// A single tab is no choice, so its bar is dropped and the group bar takes
  /// its place — which is where an IPTV session spends its time anyway.
  /// Under the redesign the views are chosen behind "Live-TV" instead — see
  /// [ockerRailMenu] — and there is no tab row to show or to focus.
  bool get _showTabChips => _visibleTabs.length > 1 && !isOckerLayout(context);

  /// Where UP from the guide content goes: the group bar when it is shown,
  /// the tab bar when that is, and otherwise the app bar actions — a
  /// guide-only session with no groups still needs a way up.
  void _focusChannelBar() {
    // Under the redesign there is no group bar and no tab row on the screen
    // at all, so the node this would otherwise ask for is attached to nothing
    // and the press lands nowhere. The rail holds the page's views, which is
    // what BACK out of the schedule is reaching for.
    if (isOckerLayout(context)) {
      MainScreenFocusScope.focusSidebarOf(context);
      return;
    }
    // The groups are the column LEFT of the channels, not a bar above them.
    if (_showTabChips) {
      focusTabBar();
    } else {
      _focusAboveContent();
    }
  }

  /// Past the top of the content there is the app bar, or — where the rail
  /// carries the actions and the bar is gone — the sidebar. Something has to
  /// take the focus either way: a press that lands nowhere strands it.
  void _focusAboveContent() {
    final actionBar = _actionBarKey.currentState;
    if (actionBar != null) {
      _setState(() => suppressAutoFocus = true);
      actionBar.requestFocusOnFirst();
      return;
    }
    MainScreenFocusScope.focusSidebarOf(context);
  }

  /// The group bar: one chip per group, LEFT/RIGHT to walk them and SELECT to
  /// scope the guide. Deliberately not switching on focus alone — that would
  /// reload the guide for every chip passed over.
  /// The groups as a column beside the channels.
  ///
  /// A list, not a strip: it is read down the side of the screen, so the
  /// labels have room to be words instead of chips that elide. Width is
  /// animated from zero, which is what pushes the rest of the screen across
  /// rather than covering it.
  Widget _buildGroupColumn() {
    final tk = Theme.of(context).extension<MonoTokens>();
    final options = _channelGroupOptions;
    final width = _groupColumnOpen ? _groupColumnWidth(context) : 0.0;
    // The ground, not a surface tint: this column stands in front of a
    // schedule, and a translucent plate over a grid of programmes is a grid of
    // programmes read through a haze.
    final ground = tk?.bg ?? Theme.of(context).scaffoldBackgroundColor;
    final glass = ockerGlass(context);
    // A Material of its own, so the rows' ink paints above the column's
    // ground rather than under it.
    final list = Material(
      type: MaterialType.transparency,
      child: ListView.builder(
        controller: _groupColumnScroll,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: options.length,
        itemBuilder: (context, i) => _GroupColumnRow(
          focusNode: _groupChipFocusNode(options[i].key),
          selected: options[i].key == _selectedGroup,
          label: options[i].label,
          count: options[i].count,
          onTap: () {
            _selectGroup(options[i].key);
            _closeGroupColumn();
          },
          // Rename or hide: held SELECT, as it was on the bar of groups this
          // column replaced. "All channels" is ours, not the provider's —
          // nothing to rename, and hiding it would leave no way back.
          onLongPress: switch (options[i].key) {
            final group? => () => unawaited(_showGroupMenu(group)),
            null => null,
          },
        ),
      ),
    );

    return AnimatedContainer(
      duration: DevicePerformance.reducedDuration(const Duration(milliseconds: 180)),
      curve: Curves.easeOutCubic,
      width: width,
      // No decoration here, deliberately. Ground and rule sit *inside* the clip
      // and below the band (the DecoratedBox further down): on this box the
      // rule ran the whole height — straight through the row of destinations —
      // and a closed column is a box of zero width whose border still paints,
      // leaving a hairline down the screen's left edge.
      // Clipped rather than laid out narrower: the rows keep their full width
      // through the whole animation and slide in, instead of squeezing.
      child: ClipRect(
        // A closed column is a box of zero width whose rows are all still
        // there, still focusable — so the cursor could walk into something
        // nobody can see, and LEFT on the guide then reached this list's own
        // handler instead of opening the column again. Painted while it
        // animates shut, reachable only while it is open.
        child: ExcludeFocus(
          excluding: !_groupColumnOpen,
          child: OverflowBox(
            alignment: .centerLeft,
            minWidth: _groupColumnWidth(context),
            maxWidth: _groupColumnWidth(context),
            // The way back out. A list tile answers SELECT and nothing else, so
            // without this the column is somewhere focus goes and does not
            // return from — LEFT would wander off by traversal and BACK would
            // leave Live TV altogether, from a column the viewer thinks of as a
            // drawer over the guide.
            child: Focus(
              onFocusChange: _onGroupColumnFocusChange,
              onKeyEvent: (node, event) {
                // Past the column there is only the navigation, so both ways
                // out lead there: the column sits where the rail and the header
                // do, and stepping off it should feel like stepping onto them
                // rather than being thrown back at the schedule.
                if (event.logicalKey.isBackKey) {
                  return handleBackKeyAction(event, _leaveGroupColumnForNavigation);
                }
                if (!event.isActionable) return KeyEventResult.ignored;
                if (event.logicalKey.isLeftKey) {
                  _leaveGroupColumnForNavigation();
                  return KeyEventResult.handled;
                }
                // And RIGHT is the way back to the schedule — spelled out here
                // rather than left to traversal, which walked into the guide
                // while the column stayed open behind it.
                if (event.logicalKey.isRightKey) {
                  _closeGroupColumn(resumeWhereItWas: true);
                  return KeyEventResult.handled;
                }
                // UP or DOWN past the first or last group stays on it
                // (Plebz): traversal would walk out of the column, which then
                // shut and opened again elsewhere.
                final direction = event.logicalKey.isDownKey
                    ? TraversalDirection.down
                    : event.logicalKey.isUpKey
                    ? TraversalDirection.up
                    : null;
                if (direction != null) {
                  final current = FocusManager.instance.primaryFocus;
                  final nodes = [for (final option in _channelGroupOptions) _groupChipFocusNode(option.key)];
                  final at = current == null ? -1 : nodes.indexOf(current);
                  if (at < 0) return KeyEventResult.ignored;
                  final next = at + (direction == TraversalDirection.down ? 1 : -1);
                  if (next < 0 || next >= nodes.length) return KeyEventResult.handled;
                  nodes[next].requestFocus();
                  if (nodes[next].context case final rowContext?) {
                    Scrollable.ensureVisible(
                      rowContext,
                      alignmentPolicy: next > at
                          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
                          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
                    );
                  }
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              // The redesign's top margin. Outside the scrollable, not as its
              // padding: padding is part of what scrolls, so the rows would
              // travel up into it.
              child: Padding(
                // Flat (Plebz): the column runs the full height, square; its
                // rows start where the content does. Glas: the panel keeps the
                // same room to the screen's top as to its foot (the viewer's
                // call), so no margin over it.
                padding: EdgeInsets.only(
                  top: isOckerLayout(context) && !ockerFlat(context) && !glass ? ockerContentTop(context) : 0,
                ),
                child: glass && ockerFlat(context)
                    ? OckerGlass(
                        borderRadius: BorderRadius.zero,
                        scrimInset: 0,
                        child: Padding(
                          padding: EdgeInsets.only(top: isOckerLayout(context) ? ockerContentTop(context) : 0),
                          child: list,
                        ),
                      )
                    : glass
                    // Under glass a panel floating clear of the edges, its
                    // corners concentric with the rows' — their corner and
                    // the room round them — and lit at its edge; nearly
                    // opaque, because a schedule read through a haze is
                    // still a haze.
                    ? Padding(
                        padding: EdgeInsets.all(12 * ockerScale(context)),
                        child: OckerGlass(
                          borderRadius: BorderRadius.circular((tk?.radiusSm ?? 14) + 8),
                          scrimInset: 0,
                          child: ClipRRect(borderRadius: BorderRadius.circular((tk?.radiusSm ?? 14) + 8), child: list),
                        ),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: ground,
                          border: Border(right: BorderSide(color: tk?.ink(0.12) ?? Theme.of(context).dividerColor)),
                        ),
                        child: list,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A quarter of the screen, within reason: wide enough for a group's name on
  /// two lines, narrow enough that the schedule beside it still shows more
  /// than one programme.
  double _groupColumnWidth(BuildContext context) =>
      (MediaQuery.sizeOf(context).width * 0.22).clamp(220.0, 360.0).toDouble();

  /// The group bar's context menu, on a held SELECT or a long press.
  ///
  /// Both entries act on the group the provider defined, not on the label:
  /// renaming leaves the channels where they are, and a hidden group can be
  /// brought back from the channel-management sheet.
  Future<void> _showGroupMenu(String groupKey) async {
    final provider = _layoutProvider;
    if (provider == null) return;
    final renamed = provider.layout.groupNames.containsKey(groupKey);
    final action = await showOptionPickerDialog<_GroupMenuAction>(
      context,
      title: _groupLabel(groupKey),
      options: [
        (icon: Symbols.edit_rounded, label: t.liveTv.renameGroup, value: _GroupMenuAction.rename),
        if (renamed)
          (icon: Symbols.undo_rounded, label: t.liveTv.restoreGroupName, value: _GroupMenuAction.restoreName),
        (icon: Symbols.visibility_off_rounded, label: t.liveTv.hideGroup, value: _GroupMenuAction.hide),
      ],
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _GroupMenuAction.rename:
        final name = await showTextInputDialog(
          context,
          title: t.liveTv.renameGroup,
          labelText: t.liveTv.groupNameLabel,
          initialValue: _groupLabel(groupKey),
        );
        if (name == null || !mounted) return;
        await provider.setGroupName(groupKey, name);
      case _GroupMenuAction.restoreName:
        await provider.setGroupName(groupKey, null);
      case _GroupMenuAction.hide:
        await provider.setGroupHidden(groupKey, true);
        // The chip is gone with the group, and a focus node with nothing
        // behind it strands the cursor in an empty row.
        if (mounted) _groupChipFocusNode(null).requestFocus();
    }
    if (mounted) _setState(() {});
  }

  /// A channel's own menu, on a held SELECT, the context-menu key or a long
  /// press on its logo in the guide: favourite, rename, hide — what the group
  /// bar offers for a group, and what a hold used to do alone (it toggled the
  /// favourite, silently).
  ///
  /// Renaming and hiding act on the channel the provider defined: the new
  /// name is shown wherever the channel is, and a hidden channel comes back
  /// from the channel-management sheet.
  Future<void> _showChannelMenu(LiveTvChannel channel) async {
    final provider = _layoutProvider;
    final channelKey = liveTvLayoutChannelKey(channel);
    final renamed = provider?.layout.channelNames.containsKey(channelKey) ?? false;
    final action = await showOptionPickerDialog<_ChannelMenuAction>(
      context,
      title: channel.displayName,
      options: [
        _isFavoriteChannel(channel)
            ? (icon: Symbols.star_rounded, label: t.liveTv.removeFromFavorites, value: _ChannelMenuAction.favorite)
            : (icon: Symbols.star_outline_rounded, label: t.liveTv.addToFavorites, value: _ChannelMenuAction.favorite),
        if (provider != null) ...[
          (icon: Symbols.edit_rounded, label: t.liveTv.renameChannel, value: _ChannelMenuAction.rename),
          if (renamed)
            (icon: Symbols.undo_rounded, label: t.liveTv.restoreGroupName, value: _ChannelMenuAction.restoreName),
          (icon: Symbols.visibility_off_rounded, label: t.liveTv.hideChannel, value: _ChannelMenuAction.hide),
        ],
      ],
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _ChannelMenuAction.favorite:
        _toggleFavorite(channel);
      case _ChannelMenuAction.rename:
        final name = await showTextInputDialog(
          context,
          title: t.liveTv.renameChannel,
          labelText: t.liveTv.channelNameLabel,
          initialValue: channel.displayName,
        );
        if (name == null || !mounted) return;
        await provider?.setChannelName(channelKey, name);
      case _ChannelMenuAction.restoreName:
        await provider?.setChannelName(channelKey, null);
      case _ChannelMenuAction.hide:
        await provider?.setChannelHidden(channelKey, true);
        if (mounted) showSnackBar(context, t.liveTv.channelHidden(name: channel.displayName));
    }
  }
}

/// One group in the column.
///
/// The redesign's list tile draws its own hairline ring; every other theme
/// leaves focus to Material's pale plate under the row, which on a television
/// at this size is not a mark at all — the viewer could not tell which group
/// the cursor was on. So outside the redesign the row carries the same focus
/// treatment the action bars use, and inside it nothing is added, because one
/// state must not have two marks.
class _GroupColumnRow extends StatefulWidget {
  const _GroupColumnRow({
    required this.focusNode,
    required this.selected,
    required this.label,
    required this.count,
    required this.onTap,
    this.onLongPress,
  });

  final FocusNode focusNode;
  final bool selected;
  final String label;
  final int count;
  final VoidCallback onTap;

  /// A held SELECT, or a long press with a pointer.
  final VoidCallback? onLongPress;

  @override
  State<_GroupColumnRow> createState() => _GroupColumnRowState();
}

class _GroupColumnRowState extends State<_GroupColumnRow> {
  final _selectHold = DpadSelectLongPressController();

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    _selectHold.reset();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) _selectHold.reset();
    if (mounted) setState(() {});
  }

  /// SELECT held on the row: the group's own menu. Seen before the row's own
  /// activation, which would otherwise take the key down as a tap.
  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final onLongPress = widget.onLongPress;
    if (onLongPress == null) return KeyEventResult.ignored;
    if (SelectKeyUpSuppressor.consumeIfSuppressed(event)) return KeyEventResult.handled;
    if (event.isActionable && event.logicalKey.isContextMenuKey) {
      _selectHold.reset();
      onLongPress();
      return KeyEventResult.handled;
    }
    return _selectHold.handleKeyEvent(
      event,
      isOwnerActive: () => mounted,
      onShortPress: widget.onTap,
      onLongPress: onLongPress,
    );
  }

  @override
  Widget build(BuildContext context) {
    final glass = ockerGlass(context);
    final tile = FocusableListTile(
      focusNode: widget.focusNode,
      selected: widget.selected,
      title: Text(widget.label, maxLines: 2, overflow: TextOverflow.ellipsis),
      // Quieter than the name: under the redesign it is a count, not a title.
      subtitle: Text(
        t.liveTv.channelCount(count: widget.count),
        style: isOcker(context) ? TextStyle(color: tokens(context).ink(0.5)) : null,
      ),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      glassMarks: true,
    );
    final keyed = Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onKey, child: tile);
    // Under glass the marks are panes, and a pane wants air round it.
    if (glass) return Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), child: keyed);
    if (isOcker(context)) return keyed;

    final showFocus = widget.focusNode.hasFocus && InputModeTracker.isKeyboardMode(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: DecoratedBox(
        decoration: FocusTheme.focusBackgroundDecoration(isFocused: showFocus, borderRadius: 10),
        // The row's ink paints on the nearest Material; this one, not one
        // under the fill, where the fill would hide it.
        child: Material(type: MaterialType.transparency, child: keyed),
      ),
    );
  }
}
