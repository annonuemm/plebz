import 'dart:async';
import 'dart:io' show Platform;
import '../../media/ids.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../exceptions/media_server_exceptions.dart';
import '../../focus/focusable_action_bar.dart';
import '../../i18n/strings.g.dart';
import '../../media/live_tv_support.dart';
import '../../media/media_server_client.dart';
import '../../models/livetv_channel.dart';
import '../../models/livetv_program.dart';
import '../../mixins/refreshable.dart';
import '../../mixins/tab_navigation_mixin.dart';
import '../../models/live_tv_channel_layout.dart';
import '../../providers/iptv_sources_provider.dart';
import '../../providers/live_tv_channel_layout_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/iptv/iptv_live_tv_source.dart';
import '../../services/live_tv_last_selection.dart';
import '../../services/settings_service.dart';
import '../../widgets/settings_builder.dart';
import '../../utils/app_logger.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/desktop_window_padding.dart';
import '../../utils/dialogs.dart';
import '../../utils/live_tv_group_label.dart';
import '../../utils/live_tv_matching.dart';
import '../../utils/platform_detector.dart';
import '../../utils/serial_future_queue.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/focusable_tab_chip.dart';
import '../../widgets/overlay_sheet.dart';
import '../../navigation/main_screen_scope.dart';
import '../libraries/state_messages.dart';
import 'channel_management_sheet.dart';
import 'guide_search_sheet.dart';
import 'live_tv_server_iteration.dart';
import 'live_tv_sidebar_actions.dart';
import 'reorder_favorites_sheet.dart';
import 'tabs/guide_tab.dart';
import 'tabs/recordings_tab.dart';
import 'tabs/whats_on_tab.dart';
import '../../focus/dpad_navigator.dart';
import '../../focus/dpad_select_long_press_controller.dart';
import '../../focus/focus_theme.dart';
import '../../focus/input_mode_tracker.dart';
import '../../focus/key_event_utils.dart';
import '../../services/device_performance.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../redesign/ocker_skin.dart';
import '../../widgets/app_menu.dart';
import '../../redesign/ocker_submenu.dart';

typedef _FavoriteScope = ({String source, String storeKey, FavoriteChannelPersistenceMode mode});

/// One chip of the group bar: a channel group and how many channels it holds.
/// The "all channels" chip carries a null key.
typedef ChannelGroupOption = ({String? key, String label, int count});

/// What the group bar's context menu offers.
enum _GroupMenuAction { rename, restoreName, hide }

enum LiveTvTab { guide, whatsOn, recordings }

class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key});

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen>
    with TickerProviderStateMixin, TabNavigationMixin, OckerSubmenuHost
    implements FocusableTab, ManualRefreshable, LiveTvSidebarActions {
  final _guideTabFocusNode = FocusNode(debugLabel: 'tab_chip_guide');
  final _whatsOnTabFocusNode = FocusNode(debugLabel: 'tab_chip_whats_on');
  final _recordingsTabFocusNode = FocusNode(debugLabel: 'tab_chip_recordings');
  final _guideTabKey = GlobalKey<GuideTabState>();
  final _whatsOnTabKey = GlobalKey<WhatsOnTabState>();
  final _recordingsTabKey = GlobalKey<RecordingsTabState>();

  /// Focus target for the "Show all channels" action shown when the favorites
  /// filter empties the guide; lets D-pad users reach the action from the tab bar.
  final _guideEmptyStateActionFocusNode = FocusNode(debugLabel: 'guide_empty_state_action');

  /// Visible tabs in the current session. What's On is included only when a
  /// Live TV server is Plex (the only backend with Live TV hubs), Recordings
  /// only when at least one Live TV server has `liveTvDvr` capability.
  List<LiveTvTab> _visibleTabs = [LiveTvTab.guide];

  /// Whether any connected DVR supports Plex-style rule re-evaluation;
  /// gates the recordings tab's bolt action.
  bool _canProcessRules = false;

  // App bar action bar
  final _actionBarKey = GlobalKey<FocusableActionBarState>();

  /// Every channel the backends returned, before the user's arrangement.
  /// Kept so the management sheet can offer back what it hides.
  List<LiveTvChannel> _loadedChannels = [];

  /// [_loadedChannels] with hidden groups and channels removed and the user's
  /// order applied — what every surface below works on.
  List<LiveTvChannel> _channels = [];
  bool _isLoading = true;
  String? _error;

  /// Selected channel group (playlist `group-title` / Xtream category), or
  /// null for all of them. IPTV sources ship hundreds of channels across
  /// dozens of groups, so the guide is scoped to one at a time.
  String? _selectedGroup;

  /// One focus node per group chip, keyed by the chip's group ('' is the
  /// "all channels" chip). Kept across rebuilds so D-pad focus survives a
  /// channel reload.
  final Map<String, FocusNode> _groupChipFocusNodes = {};

  LiveTvChannelLayoutProvider? _layoutProvider;

  /// Followed for the logos an IPTV guide gives channels whose playlist entry
  /// has none — see [_applyEpgLogos].
  IptvSourcesProvider? _iptvProvider;

  // Favorites
  bool _showFavoritesOnly = false;
  Set<String> _favoriteKeys = {};
  List<FavoriteChannel> _favoriteChannels = [];

  /// Favorite source URI, store key and persistence mode per Live TV server/DVR.
  /// The source is built from machineIdentifier + EPG provider identifier.
  final Map<String, _FavoriteScope> _favoriteScopeByLiveServer = {};
  final Map<String, String> _liveServerKeyByChannel = {};

  /// Store key per favorite source. A superset of the scope sources: it also
  /// collects sources of fetched and toggled favorites that belong to other
  /// servers sharing an account-scoped store.
  final Map<String, String> _favoriteStoreBySource = {};
  Future<void>? _channelsLoadFuture;
  int _favoritesLoadGeneration = 0;
  Future<void>? _favoritesLoadFuture;
  final SerialFutureQueue _favoritesMutationQueue = SerialFutureQueue();

  /// True while [_favoriteChannels] holds an authoritative set. A refresh keeps the previous set live until the new
  /// one commits, so the favorites filter never widens mid-load.
  bool _favoritesLoaded = false;
  bool _favoritesWritable = false;

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

  bool _groupColumnDrawerOpen = false;

  /// The group column's list. It keeps its place while the column is shut, so
  /// opening it can find the chosen group scrolled out of what the list built.
  final _groupColumnScroll = ScrollController();

  /// Whether the cursor has actually been inside the column yet.
  ///
  /// It is not, for the frame between opening the column and focusing its
  /// first row — and a "focus left the column" rule that did not know this
  /// would close it again before anybody saw it.
  bool _groupColumnHadFocus = false;

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
    setState(() => _groupColumnDrawerOpen = true);
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
    if (!_groupColumnPinned) setState(() => _groupColumnDrawerOpen = false);
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

  List<LiveTvChannel> get _filteredChannels => filterLiveTvChannelsForFavorites(
    channels: _groupedChannels,
    favoritesOnly: _showFavoritesOnly,
    favoritesLoaded: _favoritesLoaded,
    favorites: _favoriteChannels,
    sourceForChannel: _sourceForChannel,
  );

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

  /// True when the favorites filter removed every loaded channel, so the guide
  /// tab shows an explanatory empty state instead of a bare timeline.
  bool get _guideShowsFavoritesEmptyState => _channels.isNotEmpty && _filteredChannels.isEmpty;

  String _liveServerScopeKey(LiveTvServerInfo serverInfo) => '${serverInfo.serverId}\u0000${serverInfo.dvrKey}';

  _FavoriteScope? _favoriteScopeForChannel(LiveTvChannel channel) {
    final liveServerKey = _liveServerKeyByChannel[liveTvChannelScopeKey(channel)];
    return liveServerKey == null ? null : _favoriteScopeByLiveServer[liveServerKey];
  }

  String _sourceForChannel(LiveTvChannel channel) {
    return channel.favoriteSource ?? _favoriteScopeForChannel(channel)?.source ?? '';
  }

  String _favoriteKeyForChannel(LiveTvChannel channel) => favoriteChannelKey(_sourceForChannel(channel), channel.key);

  bool _isFavoriteChannel(LiveTvChannel channel) => _favoriteKeys.contains(_favoriteKeyForChannel(channel));

  void _refreshFavoriteKeys() {
    _favoriteKeys = _favoriteChannels.map((f) => f.stableKey).toSet();
  }

  @override
  List<FocusNode> get tabChipFocusNodes => [for (final tab in _visibleTabs) _focusNodeForTab(tab)];

  FocusNode _focusNodeForTab(LiveTvTab tab) => switch (tab) {
    LiveTvTab.guide => _guideTabFocusNode,
    LiveTvTab.whatsOn => _whatsOnTabFocusNode,
    LiveTvTab.recordings => _recordingsTabFocusNode,
  };

  @override
  void initState() {
    super.initState();
    suppressAutoFocus = true;
    _showFavoritesOnly = context.settingsRead(SettingsService.liveTvDefaultFavorites);
    final initialTabs = _tabStateFor(context.read<MultiServerProvider>());
    _visibleTabs = initialTabs.tabs;
    _canProcessRules = initialTabs.canProcessRules;
    initTabNavigation();
    // Followed rather than polled on return: the player records as it zaps,
    // and this screen sits behind it, so by the time the player closes the
    // guide is already on the channel that was being watched.
    LiveTvLastSelection.instance.addListener(_adoptPlayerSelection);
    _loadChannels();
  }

  /// Adopt where the player ended up, so leaving it lands on the channel and
  /// group that were being watched — not on the ones this screen was showing
  /// when the player was opened.
  void _adoptPlayerSelection() {
    final selection = LiveTvLastSelection.instance;
    if (!selection.hasSelection || !mounted) return;
    final group = selection.group;
    if (group != _selectedGroup) {
      setState(() => _selectedGroup = group);
    }
    final key = selection.channelKey;
    if (key == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _guideTabKey.currentState?.showChannel(key);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hiding or reordering happens in a sheet over this screen, so the
    // arrangement is re-applied here rather than by reloading the channels.
    final layoutProvider = context.read<LiveTvChannelLayoutProvider?>();
    if (layoutProvider != _layoutProvider) {
      _layoutProvider?.removeListener(_onChannelLayoutChanged);
      _layoutProvider = layoutProvider;
      _layoutProvider?.addListener(_onChannelLayoutChanged);
    }
    final iptvProvider = context.read<IptvSourcesProvider?>();
    if (iptvProvider != _iptvProvider) {
      _iptvProvider?.epgLogoRevision.removeListener(_applyEpgLogos);
      _iptvProvider = iptvProvider;
      _iptvProvider?.epgLogoRevision.addListener(_applyEpgLogos);
    }
  }

  /// The guide arrives after the channels, and can name logos their playlist
  /// entries lack. Patched into the list on screen rather than reloading it:
  /// that would ask every server for its channels again for a picture.
  void _applyEpgLogos() {
    final iptv = _iptvProvider;
    if (!mounted || iptv == null) return;
    var changed = false;
    final patched = <LiveTvChannel>[];
    for (final channel in _loadedChannels) {
      final withLogo = iptv.withEpgLogo(channel);
      if (!identical(withLogo, channel)) changed = true;
      patched.add(withLogo);
    }
    if (!changed) return;
    _loadedChannels = patched;
    _applyChannelLayout();
  }

  @override
  void dispose() {
    _groupColumnScroll.dispose();
    LiveTvLastSelection.instance.removeListener(_adoptPlayerSelection);
    _layoutProvider?.removeListener(_onChannelLayoutChanged);
    _iptvProvider?.epgLogoRevision.removeListener(_applyEpgLogos);
    for (final node in _groupChipFocusNodes.values) {
      node.dispose();
    }
    _guideTabFocusNode.dispose();
    _whatsOnTabFocusNode.dispose();
    _recordingsTabFocusNode.dispose();
    _guideEmptyStateActionFocusNode.dispose();
    _sidebarRevision.dispose();
    disposeTabNavigation();
    super.dispose();
  }

  /// Re-derive the visible channel list from [_loadedChannels].
  /// The arrangement changed in the sheet. An IPTV guide is read only for the
  /// channels showing, so one shown again has no programmes yet: the guide
  /// asks again, and the source reads its guide for it — the guide only, not
  /// the playlist.
  void _onChannelLayoutChanged() {
    if (!mounted) return;
    final before = {for (final channel in _channels) liveTvChannelScopeKey(channel)};
    _applyChannelLayout();
    if (_channels.any((channel) => !before.contains(liveTvChannelScopeKey(channel)))) {
      _guideTabKey.currentState?.reloadPrograms();
    }
  }

  void _applyChannelLayout() {
    if (!mounted) return;
    final layout = _layoutProvider?.layout ?? LiveTvChannelLayout.empty;
    final channels = applyLiveTvChannelLayout(_loadedChannels, layout);
    setState(() {
      _channels = channels;
      // A group that was hidden or that the reload no longer carries would
      // filter the guide down to nothing with no way back except the sheet.
      if (_selectedGroup != null && !channels.any((c) => liveTvNonEmpty(c.lineup) == _selectedGroup)) {
        _selectedGroup = null;
      }
    });
  }

  FocusNode _groupChipFocusNode(String? group) =>
      _groupChipFocusNodes.putIfAbsent(group ?? '', () => FocusNode(debugLabel: 'group_chip_${group ?? 'all'}'));

  // ---------- LiveTvSidebarActions ----------

  /// Bumped whenever one of the answers below changes.
  final ValueNotifier<int> _sidebarRevision = ValueNotifier<int>(0);

  void _notifySidebar() => _sidebarRevision.value++;

  @override
  Listenable get sidebarRevision => _sidebarRevision;
  //
  // The sidebar drives these; the screen's own app bar is gone wherever the
  // rail is on screen (see [build]).

  @override
  bool get canManageChannels => _loadedChannels.isNotEmpty && _layoutProvider != null;

  @override
  bool get showsFavoritesOnly => _showFavoritesOnly;

  @override
  bool get canReorderFavorites => _showFavoritesOnly && _favoriteChannels.length > 1;

  @override
  void openChannelManagement() => _showChannelManagement();

  @override
  void toggleFavoritesFilter() => _toggleFavoritesFilter();

  @override
  void reorderFavorites() => _showReorderFavorites();

  @override
  void reloadLiveTv() => _onRefresh();

  @override
  void onTabChanged() {
    if (!tabController.indexIsChanging) {
      super.onTabChanged();
      // Pause/resume timers based on active tab
      if (tabController.index >= _visibleTabs.length) return;
      switch (_visibleTabs[tabController.index]) {
        case LiveTvTab.guide:
          _whatsOnTabKey.currentState?.pauseRefresh();
          _recordingsTabKey.currentState?.pauseRefresh();
          _guideTabKey.currentState?.resumeRefresh();
        case LiveTvTab.whatsOn:
          _guideTabKey.currentState?.pauseRefresh();
          _recordingsTabKey.currentState?.pauseRefresh();
          _whatsOnTabKey.currentState?.resumeRefresh();
        case LiveTvTab.recordings:
          _guideTabKey.currentState?.pauseRefresh();
          _whatsOnTabKey.currentState?.pauseRefresh();
          _recordingsTabKey.currentState?.resumeRefresh();
      }
    }
  }

  LiveTvTab? get _currentTab {
    if (tabController.index < 0 || tabController.index >= _visibleTabs.length) return null;
    return _visibleTabs[tabController.index];
  }

  /// The menu's own values for its actions; views are their index.
  static const _manageChannelsEntry = -1;
  static const _favoritesEntry = -2;
  static const _reorderFavoritesEntry = -3;
  static const _reloadEntry = -4;

  /// Under the redesign the rows under "Live-TV" in the side rail are where
  /// everything the page has besides its content lives: its views, then what
  /// the app bar holds in the other themes — "Sender verwalten", the
  /// favourites filter and their order, and reloading the guide. There is no
  /// tab row and no app bar for them; without "Sender verwalten" a hidden
  /// group could never be shown again. The groups are not here — they are the
  /// column LEFT of the channels.
  @override
  OckerRailMenu? get ockerRailMenu => OckerRailMenu.fromEntries(_ockerMenuEntries(), _onOckerMenuChosen);

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
        setState(() => tabController.index = chosen);
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

  @override
  void manualRefresh() => unawaited(_onRefresh());

  /// Tab-aware refresh handler bound to the AppBar refresh button.
  /// - Guide / What's On: server-side `reloadGuide` per DVR-capable client +
  ///   client-side channel re-fetch.
  /// - Recordings: re-fetches scheduled recordings + rules.
  Future<void> _onRefresh() async {
    if (_currentTab == LiveTvTab.recordings) {
      await _recordingsTabKey.currentState?.reload();
      return;
    }
    // A server reloads its guide on request; an IPTV source has nobody to
    // ask, so refreshing it means dropping the cached playlist and guide and
    // reading them again.
    context.read<IptvSourcesProvider?>()?.refreshAll();
    await _broadcastToDvrs(
      actionLabel: 'Reload guide',
      successMessage: t.liveTv.guideReloadRequested,
      failureMessage: t.liveTv.guideReloadFailed,
      action: (dvr, serverInfo) => dvr.reloadGuide(serverInfo.dvrKey),
    );
    await _loadChannels();
  }

  /// Runs [action] on every DVR-capable Live TV server in parallel, then
  /// reports the outcome: [successMessage] once every DVR accepted the
  /// request, otherwise an error naming the failure — `dvrAdminRequired`
  /// when every failure was a 403 (admin only), else [failureMessage].
  /// Per-DVR failures never abort the broadcast; they are logged under
  /// [actionLabel] and the remaining DVRs still run, since callers re-fetch
  /// their own client-side state regardless. Returns `true` once at least
  /// one DVR was reached and this widget is still mounted.
  Future<bool> _broadcastToDvrs({
    required String actionLabel,
    required String successMessage,
    required String failureMessage,
    required Future<void> Function(LiveTvDvrSupport dvr, LiveTvServerInfo serverInfo) action,
  }) async {
    final multiServer = context.read<MultiServerProvider>();
    var failed = 0;
    var adminBlocked = 0;
    Future<void> runSafely(LiveTvDvrSupport dvr, LiveTvServerInfo serverInfo) async {
      try {
        await action(dvr, serverInfo);
      } catch (e, stackTrace) {
        failed++;
        if (e is MediaServerHttpException && e.statusCode == 403) adminBlocked++;
        appLogger.w('$actionLabel failed for DVR ${serverInfo.dvrKey}', error: e, stackTrace: stackTrace);
      }
    }

    final futures = <Future<void>>[];
    for (final serverInfo in multiServer.liveTvServers) {
      final dvr = multiServer.getClientForServer(ServerId(serverInfo.serverId))?.liveTvDvr;
      if (dvr == null) continue;
      futures.add(runSafely(dvr, serverInfo));
    }
    if (futures.isEmpty) return false;
    await Future.wait(futures);
    if (!mounted) return false;
    if (failed == 0) {
      showSnackBar(context, successMessage);
    } else {
      final message = adminBlocked == failed ? t.liveTv.dvrAdminRequired : failureMessage;
      showSnackBar(context, message, type: SnackBarType.error);
    }
    return true;
  }

  Future<void> _processRecordingRules() async {
    final reached = await _broadcastToDvrs(
      actionLabel: 'processRecordingRules',
      successMessage: t.liveTv.rulesProcessRequested,
      failureMessage: t.liveTv.rulesProcessFailed,
      action: (dvr, _) => dvr.processRecordingRules(),
    );
    if (!reached) return;
    await _recordingsTabKey.currentState?.reload();
  }

  ({List<LiveTvTab> tabs, bool canProcessRules}) _tabStateFor(MultiServerProvider multiServer) {
    var hasPlexServer = false;
    var hasDvr = false;
    var canProcessRules = false;
    for (final s in multiServer.liveTvServers) {
      final serverId = ServerId(s.serverId);
      // What's On lists Plex's Live TV hubs; Jellyfin and Emby have none, so
      // the tab would only ever be empty for them.
      hasPlexServer = hasPlexServer || multiServer.getPlexClientForServer(serverId) != null;
      final dvr = multiServer.getClientForServer(serverId)?.liveTvDvr;
      if (dvr == null) continue;
      hasDvr = true;
      canProcessRules = canProcessRules || dvr.supportsRuleProcessing;
    }
    return (
      tabs: [LiveTvTab.guide, if (hasPlexServer) LiveTvTab.whatsOn, if (hasDvr) LiveTvTab.recordings],
      canProcessRules: canProcessRules,
    );
  }

  /// Recompute visible tabs from the current MultiServerProvider state.
  /// Re-inits the tab controller when the visible set changes (matches the
  /// libraries-screen pattern at libraries_screen.dart:365).
  void _refreshVisibleTabs(MultiServerProvider multiServer) {
    final (tabs: newTabs, :canProcessRules) = _tabStateFor(multiServer);
    if (canProcessRules != _canProcessRules) {
      setState(() => _canProcessRules = canProcessRules);
    }
    if (listEquals(_visibleTabs, newTabs)) return;
    final currentTab = tabController.index < _visibleTabs.length ? _visibleTabs[tabController.index] : null;
    disposeTabNavigation();
    _visibleTabs = newTabs;
    initTabNavigation();
    if (currentTab != null) {
      final newIndex = newTabs.indexOf(currentTab);
      if (newIndex >= 0) tabController.index = newIndex;
    }
  }

  String? _sourceTitleForServerInfo(LiveTvServerInfo serverInfo) {
    for (final dvr in serverInfo.dvrs) {
      if (dvr.key == serverInfo.dvrKey) {
        return liveTvNonEmpty(dvr.lineupTitle) ?? liveTvNonEmpty(dvr.lineupURL) ?? liveTvNonEmpty(dvr.lineup);
      }
    }
    return liveTvNonEmpty(serverInfo.lineup);
  }

  Future<void> _loadChannels() {
    final inFlight = _channelsLoadFuture;
    if (inFlight != null) return inFlight;
    late final Future<void> load;
    load = _loadChannelsOnce().whenComplete(() {
      if (identical(_channelsLoadFuture, load)) _channelsLoadFuture = null;
    });
    _channelsLoadFuture = load;
    return load;
  }

  Future<void> _loadChannelsOnce() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final multiServer = context.read<MultiServerProvider>();
      final liveTvServers = multiServer.liveTvServers;
      // Nullable read: hosts without the profile scope (widget tests) simply
      // have no IPTV sources.
      final iptv = context.read<IptvSourcesProvider?>();
      await iptv?.ensureLoaded();
      final iptvSources = iptv?.liveTvSources ?? const <IptvLiveTvSource>[];
      // Read before the channels land so the first frame already shows the
      // arrangement instead of the raw provider order.
      await _layoutProvider?.ensureLoaded();

      if (liveTvServers.isEmpty && iptvSources.isEmpty) {
        setState(() {
          _isLoading = false;
          _error = t.liveTv.noDvr;
        });
        return;
      }

      final allChannels = <LiveTvChannel>[];
      final seenChannels = <String>{};
      final favoriteScopeByLiveServer = <String, _FavoriteScope>{};
      final liveServerKeyByChannel = <String, String>{};
      final favoriteStoreBySource = <String, String>{};

      appLogger.d(
        'Live TV DVRs: ${liveTvServers.map((s) => '${s.serverId}/${s.dvrKey} lineup=${s.lineup}').join(', ')}',
      );

      // Build a set of enabled channel keys per Live TV DVR from cached DVR data.
      final enabledKeysByLiveServer = <String, Set<String>>{};
      for (final serverInfo in liveTvServers) {
        final enabledKeys = liveTvEnabledChannelKeys(serverInfo);
        if (enabledKeys != null) {
          enabledKeysByLiveServer[_liveServerScopeKey(serverInfo)] = enabledKeys;
        }
      }

      var serversTried = 0;
      var serversFailed = 0;
      Object? firstFailure;

      // One liveTvServers entry per DVR: visit them all; channels dedupe below.
      await forEachLiveTvServer(
        multiServer,
        resolveClient: multiServer.getClientForServer,
        dedupeByServerId: false,
        body: (genericClient, serverInfo) async {
          serversTried++;
          final liveTv = genericClient.liveTv;
          final source = await liveTv.buildFavoriteChannelSource(lineup: serverInfo.lineup);
          final sourceTitle = _sourceTitleForServerInfo(serverInfo);
          final storeKey = liveTv.favoriteStoreKey;
          final liveServerKey = _liveServerScopeKey(serverInfo);
          favoriteScopeByLiveServer[liveServerKey] = (
            source: source,
            storeKey: storeKey,
            mode: liveTv.favoritePersistenceMode,
          );
          favoriteStoreBySource[source] = storeKey;

          final channels = await genericClient.liveTv.fetchChannels(lineup: serverInfo.lineup);
          // Plex's DVR exposes a separate enabled-channel mapping; Jellyfin
          // already filters to subscribed channels server-side.
          final enabledKeys = enabledKeysByLiveServer[liveServerKey];
          appLogger.d(
            'Channels from ${serverInfo.dvrKey}: ${channels.length} channels (${enabledKeys?.length ?? 'all'} enabled)',
          );
          for (final channel in channels) {
            if (enabledKeys != null && !enabledKeys.contains(channel.key)) continue;
            final scopedChannel = channel.copyWith(
              liveDvrKey: serverInfo.dvrKey,
              liveTvSourceTitle: sourceTitle,
              favoriteSource: source,
              favoriteStoreKey: storeKey,
            );
            final dedupKey = liveTvChannelScopeKey(scopedChannel);
            if (seenChannels.add(dedupKey)) {
              liveServerKeyByChannel[dedupKey] = liveServerKey;
              allChannels.add(scopedChannel);
            }
          }
        },
        onError: (client, serverInfo, error, stackTrace) {
          serversFailed++;
          firstFailure ??= error;
          appLogger.e('Failed to load channels from server ${serverInfo.serverId}', error: error);
        },
      );

      // IPTV sources sit beside the servers: same channel model, same
      // favorites plumbing, only without a DVR to ask about enabled channels.
      // They count as sources below, so a failing server does not throw away
      // a playlist that loaded, and a failing playlist alone still reports.
      for (final source in iptvSources) {
        serversTried++;
        try {
          final favoriteSource = await source.buildFavoriteChannelSource();
          final storeKey = source.favoriteStoreKey;
          favoriteScopeByLiveServer[storeKey] = (
            source: favoriteSource,
            storeKey: storeKey,
            mode: source.favoritePersistenceMode,
          );
          favoriteStoreBySource[favoriteSource] = storeKey;

          for (final channel in await source.fetchChannels()) {
            final dedupKey = liveTvChannelScopeKey(channel);
            if (!seenChannels.add(dedupKey)) continue;
            liveServerKeyByChannel[dedupKey] = storeKey;
            allChannels.add(channel);
          }
        } catch (error, stackTrace) {
          // One unreachable playlist must not cost the other sources.
          serversFailed++;
          firstFailure ??= error;
          appLogger.e('Failed to load channels from IPTV source', error: error, stackTrace: stackTrace);
        }
      }

      final failure = firstFailure;
      if (failure != null && serversFailed == serversTried) {
        if (!mounted) return;
        // Every source failed, so there is nothing to replace the loaded
        // channels with: keep them and report the failure, or show the error
        // state when there were none (not an empty "no channels" guide).
        final message = localizedLoadErrorText(failure, context: t.liveTv.title);
        final keepChannels = _channels.isNotEmpty;
        setState(() {
          _isLoading = false;
          if (!keepChannels) _error = message;
        });
        if (keepChannels) showErrorSnackBar(context, message);
        return;
      }

      allChannels.sort((a, b) {
        final aNum = double.tryParse(a.number ?? '') ?? 999999;
        final bNum = double.tryParse(b.number ?? '') ?? 999999;
        return aNum.compareTo(bNum);
      });

      if (!mounted) return;

      appLogger.d('Live TV: loaded ${allChannels.length} channels');

      setState(() {
        _loadedChannels = allChannels;
        _notifySidebar();
        _favoriteScopeByLiveServer
          ..clear()
          ..addAll(favoriteScopeByLiveServer);
        _liveServerKeyByChannel
          ..clear()
          ..addAll(liveServerKeyByChannel);
        _favoriteStoreBySource
          ..clear()
          ..addAll(favoriteStoreBySource);
        _isLoading = false;
      });
      _applyChannelLayout();

      _refreshVisibleTabs(multiServer);

      // Load favorites by backend store: Plex is cloud/account-scoped, Jellyfin per server.
      final favoritesLoad = _loadFavorites(multiServer, iptvSources);
      _favoritesLoadFuture = favoritesLoad;
      unawaited(
        favoritesLoad.whenComplete(() {
          if (identical(_favoritesLoadFuture, favoritesLoad)) {
            _favoritesLoadFuture = null;
          }
        }),
      );

      if (allChannels.isNotEmpty && PlatformDetector.shouldUseSideNavigation(context)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusCurrentTab();
        });
      }
    } catch (e, stackTrace) {
      final message = localizedLoadErrorMessage(e, stackTrace, context: t.liveTv.title);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = message;
        });
      }
    }
  }

  Future<void> _loadFavorites(MultiServerProvider multiServer, List<IptvLiveTvSource> iptvSources) async {
    final loadGeneration = ++_favoritesLoadGeneration;
    _favoritesWritable = false;
    final previousStoreBySource = Map<String, String>.of(_favoriteStoreBySource);
    final scopeByLiveServer = Map<String, _FavoriteScope>.of(_favoriteScopeByLiveServer);
    final storeBySource = Map<String, String>.of(_favoriteStoreBySource);
    final merged = <FavoriteChannel>[];
    final successfulStores = <String>{};
    final failedStores = <String>{};
    final seenFavorites = <String>{};

    // One liveTvServers entry per DVR: register every favorite scope, but
    // fetch each favorite store only once.
    await forEachLiveTvServer(
      multiServer,
      resolveClient: multiServer.getClientForServer,
      dedupeByServerId: false,
      body: (client, serverInfo) async {
        final liveTv = client.liveTv;
        final storeKey = liveTv.favoriteStoreKey;
        final liveServerKey = _liveServerScopeKey(serverInfo);

        final source = await liveTv.buildFavoriteChannelSource(lineup: serverInfo.lineup);
        scopeByLiveServer[liveServerKey] = (source: source, storeKey: storeKey, mode: liveTv.favoritePersistenceMode);
        storeBySource[source] = storeKey;
        if (successfulStores.contains(storeKey)) return;

        final serverFavorites = await liveTv.fetchFavoriteChannels();
        successfulStores.add(storeKey);
        failedStores.remove(storeKey);
        for (final favorite in serverFavorites) {
          storeBySource[favorite.source] = storeKey;
          if (seenFavorites.add(favorite.stableKey)) merged.add(favorite);
        }
      },
      onError: (client, serverInfo, error, stackTrace) {
        final storeKey = client.liveTv.favoriteStoreKey;
        if (!successfulStores.contains(storeKey)) failedStores.add(storeKey);
        appLogger.e('Failed to load favorite channels for $storeKey', error: error, stackTrace: stackTrace);
      },
    );

    // IPTV sources are favorite stores too — local ones, with no server to
    // ask. Registering their scope is what lets a toggled favorite find a
    // store to be written to.
    for (final source in iptvSources) {
      final storeKey = source.favoriteStoreKey;
      final favoriteSource = await source.buildFavoriteChannelSource();
      scopeByLiveServer[storeKey] = (source: favoriteSource, storeKey: storeKey, mode: source.favoritePersistenceMode);
      storeBySource[favoriteSource] = storeKey;
      if (successfulStores.contains(storeKey)) continue;
      try {
        final sourceFavorites = await source.fetchFavoriteChannels();
        successfulStores.add(storeKey);
        failedStores.remove(storeKey);
        for (final favorite in sourceFavorites) {
          storeBySource[favorite.source] = storeKey;
          if (seenFavorites.add(favorite.stableKey)) merged.add(favorite);
        }
      } catch (error, stackTrace) {
        failedStores.add(storeKey);
        appLogger.e('Failed to load favorite channels for $storeKey', error: error, stackTrace: stackTrace);
      }
    }

    // A failed store keeps its last committed in-memory slice. Healthy stores
    // still refresh, but mutations stay disabled until every store has loaded
    // so a later persist cannot replace the failed store with an empty list.
    for (final favorite in _favoriteChannels) {
      final storeKey = previousStoreBySource[favorite.source];
      if (storeKey != null && failedStores.contains(storeKey) && seenFavorites.add(favorite.stableKey)) {
        merged.add(favorite);
      }
    }

    if (!mounted || loadGeneration != _favoritesLoadGeneration) return;
    setState(() {
      _favoriteScopeByLiveServer
        ..clear()
        ..addAll(scopeByLiveServer);
      _favoriteStoreBySource
        ..clear()
        ..addAll(storeBySource);
      _favoriteChannels = merged;
      _notifySidebar();
      _refreshFavoriteKeys();
      _favoritesLoaded = failedStores.isEmpty || successfulStores.isNotEmpty || merged.isNotEmpty;
      _favoritesWritable = failedStores.isEmpty;
    });
    appLogger.d(
      'Live TV: loaded ${merged.length} favorite channels'
      '${failedStores.isEmpty ? '' : ' (${failedStores.length} store(s) deferred)'}',
    );
  }

  void _toggleFavoritesFilter() {
    setState(() {
      _showFavoritesOnly = !_showFavoritesOnly;
      _notifySidebar();
    });
  }

  /// Clears the favorites filter from the guide's empty state. When the action
  /// button owned the focus (TV/D-pad), hand focus to the guide content that
  /// replaces it so focus is not dropped.
  void _showAllChannelsFromEmptyState() {
    final hadFocus = _guideEmptyStateActionFocusNode.hasFocus;
    _toggleFavoritesFilter();
    if (!hadFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusCurrentTab();
    });
  }

  void _toggleFavorite(LiveTvChannel channel) {
    _enqueueFavoriteMutation(() {
      final source = _sourceForChannel(channel);
      final favoriteKey = favoriteChannelKey(source, channel.key);
      final storeKey = channel.favoriteStoreKey ?? _favoriteScopeForChannel(channel)?.storeKey;
      if (storeKey != null) _favoriteStoreBySource[source] = storeKey;

      setState(() {
        if (_favoriteKeys.contains(favoriteKey)) {
          _favoriteChannels = _favoriteChannels.where((f) => f.id != channel.key || f.source != source).toList();
        } else {
          _favoriteChannels = [..._favoriteChannels, FavoriteChannel.fromLiveTvChannel(channel, source)];
        }
        _refreshFavoriteKeys();
      });
    });
  }

  void _enqueueFavoriteMutation(VoidCallback mutation) {
    final pendingLoad = _favoritesLoadFuture;
    unawaited(
      _favoritesMutationQueue
          .run(() async {
            if (pendingLoad != null) await pendingLoad;
            if (!mounted) return;
            if (!_favoritesWritable) {
              showErrorSnackBar(context, t.liveTv.favoritesLoadFailed);
              return;
            }
            mutation();
            await _persistFavorites();
          })
          .catchError((Object error, StackTrace stackTrace) {
            appLogger.e('Failed to mutate favorite channels', error: error, stackTrace: stackTrace);
            if (mounted) {
              showErrorSnackBar(context, t.liveTv.favoritesUpdateFailed);
            }
          }),
    );
  }

  void _showChannelManagement() {
    unawaited(showChannelManagementSheet(context, channels: _loadedChannels));
  }

  void _showGuideSearch() {
    OverlaySheetController.showAdaptive(
      context,
      isScrollControlled: true,
      builder: (sheetContext) => GuideSearchSheet(
        channels: _channels,
        onChannelSelected: _jumpToGuideChannel,
        onProgramSelected: (channel, program) => _jumpToGuideChannel(channel, program: program),
      ),
    );
  }

  void _jumpToGuideChannel(LiveTvChannel channel, {LiveTvProgram? program}) {
    // The guide only shows favorite rows while the filter is on — drop it so
    // the target channel's row exists to land on.
    if (_showFavoritesOnly && !_isFavoriteChannel(channel)) {
      setState(() => _showFavoritesOnly = false);
    }
    // Search opens from any tab, but results live in the guide grid. A tab
    // switch builds GuideTab fresh (no keep-alive); its jump methods stash
    // the request until the initial program load completes.
    final guideIndex = _visibleTabs.indexOf(LiveTvTab.guide);
    if (guideIndex >= 0 && tabController.index != guideIndex) {
      setState(() => tabController.index = guideIndex);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final guide = _guideTabKey.currentState;
      if (guide == null) return;
      if (program != null) {
        unawaited(guide.jumpToProgram(channel, program));
      } else {
        guide.jumpToChannel(channel);
      }
    });
  }

  void _selectGroup(String? group) {
    if (group == _selectedGroup) return;
    setState(() => _selectedGroup = group);
    // The guide keeps its scroll offset across a channel-list change, so show
    // the new group from its first channel and hand focus back to the content
    // that just replaced it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _guideTabKey.currentState?.showFirstChannel();
      _focusCurrentTab();
    });
  }

  void _showReorderFavorites() {
    final channelMap = {for (final c in _channels) _favoriteKeyForChannel(c): c};

    OverlaySheetController.showAdaptive(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => ReorderFavoritesSheet(
        favorites: List.from(_favoriteChannels),
        channelMap: channelMap,
        onReorder: (reordered) {
          _enqueueFavoriteMutation(() {
            setState(() {
              _favoriteChannels = reordered;
              _refreshFavoriteKeys();
            });
          });
        },
        onRemove: (removed) {
          _enqueueFavoriteMutation(() {
            setState(() {
              _favoriteChannels = _favoriteChannels.where((f) => f.stableKey != removed.stableKey).toList();
              _refreshFavoriteKeys();
            });
          });
        },
      ),
    );
  }

  Future<void> _persistFavorites() async {
    final multiServer = context.read<MultiServerProvider>();
    final iptvSources = context.read<IptvSourcesProvider?>()?.liveTvSources ?? const <IptvLiveTvSource>[];
    final byStore = <String, List<FavoriteChannel>>{};
    for (final favorite in _favoriteChannels) {
      final storeKey = _favoriteStoreBySource[favorite.source];
      if (storeKey == null) continue;
      byStore.putIfAbsent(storeKey, () => []).add(favorite);
    }
    final writtenStores = <String>{};
    final writes = <Future<void>>[];
    for (final serverInfo in multiServer.liveTvServers) {
      final client = multiServer.getClientForServer(ServerId(serverInfo.serverId));
      if (client == null) continue;
      final scope = _favoriteScopeByLiveServer[_liveServerScopeKey(serverInfo)];
      if (scope == null || !writtenStores.add(scope.storeKey)) continue;
      final storeChannels = byStore[scope.storeKey] ?? const <FavoriteChannel>[];
      final channels = switch (scope.mode) {
        FavoriteChannelPersistenceMode.sharedFullList => storeChannels,
        FavoriteChannelPersistenceMode.serverSlice =>
          storeChannels.where((favorite) => favorite.source == scope.source).toList(),
      };
      writes.add(client.liveTv.setFavoriteChannels(channels));
    }

    // Each IPTV source owns its own local store, so its slice is simply the
    // favorites filed under that store.
    for (final source in iptvSources) {
      final storeKey = source.favoriteStoreKey;
      if (!writtenStores.add(storeKey)) continue;
      writes.add(source.setFavoriteChannels(byStore[storeKey] ?? const <FavoriteChannel>[]));
    }

    await Future.wait(writes);
  }

  void _focusCurrentTab() {
    if (tabController.index < _visibleTabs.length) {
      switch (_visibleTabs[tabController.index]) {
        case LiveTvTab.guide:
          final guideState = _guideTabKey.currentState;
          if (guideState != null) {
            guideState.focusContent();
          } else if (_guideShowsFavoritesEmptyState && _guideEmptyStateActionFocusNode.context != null) {
            _guideEmptyStateActionFocusNode.requestFocus();
          }
        case LiveTvTab.whatsOn:
          _whatsOnTabKey.currentState?.focusFirstHub();
        case LiveTvTab.recordings:
          _recordingsTabKey.currentState?.focusContent();
      }
    }
    setState(() {
      suppressAutoFocus = false;
    });
  }

  @override
  void focusActiveTabIfReady() => _focusCurrentTab();

  String _getTabLabel(LiveTvTab tab) {
    return switch (tab) {
      LiveTvTab.guide => t.liveTv.guide,
      LiveTvTab.whatsOn => t.liveTv.whatsOn,
      LiveTvTab.recordings => t.liveTv.recordings,
    };
  }

  List<Widget> _buildTabChipItems() {
    return [
      for (int i = 0; i < _visibleTabs.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        buildTabChip(
          _getTabLabel(_visibleTabs[i]),
          i,
          onSelectWhenActive: _focusCurrentTab,
          onNavigateDown: _focusCurrentTab,
          onNavigateToActions: () => _actionBarKey.currentState?.requestFocusOnFirst(),
        ),
      ],
    ];
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
      setState(() => suppressAutoFocus = true);
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
                return KeyEventResult.ignored;
              },
              // The redesign's top margin. Outside the scrollable, not as its
              // padding: padding is part of what scrolls, so the rows would
              // travel up into it.
              child: Padding(
                padding: EdgeInsets.only(top: isOckerLayout(context) ? ockerContentTop(context) : 0),
                child: glass
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
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final useSideNav = PlatformDetector.shouldUseSideNavigation(context);

    final isRecordings = _currentTab == LiveTvTab.recordings;
    // With the rail on screen the actions live there, and a bar holding
    // nothing but the screen's own name is a row of television spent on a
    // word the sidebar already says. It stays wherever the tabs need showing.
    if (useSideNav && !_showTabChips) {
      return Scaffold(body: _buildLiveTvBody(useSideNav));
    }

    return Scaffold(
      appBar: AppBar(
        title: useSideNav && _showTabChips ? TabChipStrip(children: _buildTabChipItems()) : Text(t.liveTv.title),
        actions: DesktopAppBarHelper.buildAdjustedActions([
          FocusableActionBar(
            key: _actionBarKey,
            onNavigateLeft: () => getTabChipFocusNode(tabCount - 1).requestFocus(),
            onNavigateDown: _focusCurrentTab,
            actions: [
              // Shown on every tab: the d-pad route into this bar traverses
              // the tab chips, and RIGHT selects each tab it crosses — a
              // guide-only action would be unmounted before focus could ever
              // reach it. Selecting a result switches back to the guide tab.
              FocusableAction(icon: Symbols.search_rounded, tooltip: t.liveTv.searchGuide, onPressed: _showGuideSearch),
              // Nullable provider: hosts without the profile scope (widget
              // tests) have nowhere to store an arrangement.
              if (!isRecordings && _loadedChannels.isNotEmpty && _layoutProvider != null)
                FocusableAction(
                  icon: Symbols.tune_rounded,
                  tooltip: t.liveTv.manageChannels,
                  onPressed: _showChannelManagement,
                ),
              if (!isRecordings)
                FocusableAction(
                  icon: _showFavoritesOnly ? Symbols.star_rounded : Symbols.star_outline_rounded,
                  iconFill: _showFavoritesOnly ? 1.0 : 0.0,
                  tooltip: t.liveTv.favorites,
                  onPressed: _toggleFavoritesFilter,
                ),
              if (!isRecordings && _showFavoritesOnly && _favoriteChannels.length > 1)
                FocusableAction(
                  icon: Symbols.swap_vert_rounded,
                  tooltip: t.liveTv.reorderFavorites,
                  onPressed: _showReorderFavorites,
                ),
              // Rule re-evaluation is a Plex-only server operation; hide the
              // bolt when no connected DVR supports it (MediaBrowser).
              if (isRecordings && _canProcessRules)
                FocusableAction(
                  icon: Symbols.bolt_rounded,
                  tooltip: t.liveTv.processRecordingRules,
                  onPressed: _processRecordingRules,
                ),
              FocusableAction(
                icon: Symbols.refresh_rounded,
                tooltip: isRecordings ? t.common.refresh : t.liveTv.reloadGuide,
                onPressed: manualRefresh,
              ),
            ],
          ),
        ]),
      ),
      body: _buildLiveTvBody(useSideNav),
    );
  }

  Widget _buildTabContent(LiveTvTab tab, List<LiveTvChannel> guideChannels) {
    return switch (tab) {
      LiveTvTab.guide =>
        guideChannels.isEmpty && _channels.isNotEmpty
            ? EmptyStateWidget(
                icon: Symbols.star_outline_rounded,
                message: t.liveTv.noFavoriteChannels,
                subtitle: t.liveTv.noFavoriteChannelsHint,
                actionLabel: t.liveTv.showAllChannels,
                actionIcon: Symbols.list_rounded,
                actionFocusNode: _guideEmptyStateActionFocusNode,
                onAction: _showAllChannelsFromEmptyState,
                onActionNavigateUp: _focusChannelBar,
                onActionNavigateLeft: onTabBarBack,
                onActionBack: onTabBarBack,
              )
            : GuideTab(
                key: _guideTabKey,
                channels: guideChannels,
                playerChannels: _playerChannels,
                playerGroup: _selectedGroup,
                isFavoriteChannel: _isFavoriteChannel,
                onToggleFavorite: _toggleFavorite,
                onNavigateUp: _focusChannelBar,
                onBack: onTabBarBack,
                onOpenGroups: _groupColumnEnabled ? _openGroupColumn : null,
              ),
      LiveTvTab.whatsOn => WhatsOnTab(
        key: _whatsOnTabKey,
        channels: _groupedChannels,
        playerChannels: _playerChannels,
        playerGroup: _selectedGroup,
        onNavigateUp: _focusChannelBar,
        onBack: onTabBarBack,
      ),
      LiveTvTab.recordings => RecordingsTab(
        key: _recordingsTabKey,
        onNavigateUp: _focusChannelBar,
        onBack: onTabBarBack,
      ),
    };
  }

  Widget _buildLiveTvBody(bool useSideNav) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorStateWidget(
        message: _error!,
        icon: Symbols.error_rounded,
        onRetry: _loadChannels,
        actionAutofocus: true,
        actionUseBackgroundFocus: true,
      );
    }
    if (_channels.isEmpty && !_visibleTabs.contains(LiveTvTab.recordings)) {
      return Center(child: Text(t.liveTv.noChannels));
    }

    final guideChannels = _filteredChannels;

    final body = Column(
      children: [
        if (!useSideNav && _showTabChips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            alignment: .centerLeft,
            child: TabChipStrip(children: _buildTabChipItems()),
          ),
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: [for (final tab in _visibleTabs) _buildTabContent(tab, guideChannels)],
          ),
        ),
      ],
    );

    if (!_groupColumnEnabled) return body;
    // A Row, so the column does not float over the guide: giving it width
    // takes width from everything else, which is exactly the movement asked
    // for — the schedule, the picture and the description all slide right.
    return Row(
      children: [
        _buildGroupColumn(),
        Expanded(child: body),
      ],
    );
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
