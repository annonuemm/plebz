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

part 'live_tv_screen_groups.dart';

typedef _FavoriteScope = ({String source, String storeKey, FavoriteChannelPersistenceMode mode});

/// One chip of the group bar: a channel group and how many channels it holds.
/// The "all channels" chip carries a null key.
typedef ChannelGroupOption = ({String? key, String label, int count});

/// What the group bar's context menu offers.
enum _GroupMenuAction { rename, restoreName, hide }

enum _ChannelMenuAction { favorite, rename, restoreName, hide }

enum LiveTvTab { guide, whatsOn, recordings }

class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key});

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen>
    with TickerProviderStateMixin, TabNavigationMixin, OckerSubmenuHost
    implements FocusableTab, BackgroundSelectedTab, ManualRefreshable, LiveTvSidebarActions {
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

  // The fork's listeners stay instance methods: an extension method's
  // tear-off is a new closure each time, so removeListener would miss it.

  /// Adopt where the player ended up, so leaving it lands on the channel and
  /// group that were being watched — not on the ones this screen was showing
  /// when the player was opened.
  ///
  /// A hand-off from the home screen ([LiveTvLastSelection.handOff]) also
  /// brings the guide itself forward, whichever view was on show.
  void _adoptPlayerSelection({bool handedOff = false}) {
    final selection = LiveTvLastSelection.instance;
    if (!selection.hasSelection || !mounted) return;
    if (!handedOff) handedOff = selection.takeHandOff();
    final group = selection.group;
    if (group != _selectedGroup) {
      setState(() => _selectedGroup = group);
    }
    _pendingChannelKey = selection.channelKey;
    if (handedOff) {
      final guide = _visibleTabs.indexOf(LiveTvTab.guide);
      if (guide >= 0 && tabController.index != guide) tabController.index = guide;
    }
    _showPendingChannel();
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

  /// [setState] for the fork's members in `live_tv_screen_groups.dart`: an
  /// extension is not a subclass, so it may not call the protected original.
  void _setState(VoidCallback fn) => setState(fn);

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

  List<LiveTvChannel> get _filteredChannels => filterLiveTvChannelsForFavorites(
    channels: _groupedChannels,
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
    // Built in this very moment for a channel started from the home screen:
    // the hand-off was recorded before there was anyone to listen.
    if (LiveTvLastSelection.instance.takeHandOff()) _adoptPlayerSelection(handedOff: true);
    _loadChannels();
  }

  /// The channel [_adoptPlayerSelection] is to put under the cursor, kept
  /// until the guide has it: a hand-off arrives before the channels do.
  String? _pendingChannelKey;

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

  // ---------- LiveTvSidebarActions ----------

  /// Bumped whenever one of the answers below changes.
  final ValueNotifier<int> _sidebarRevision = ValueNotifier<int>(0);

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

  /// Under the redesign the rows under "Live-TV" in the side rail are where
  /// everything the page has besides its content lives: its views, then what
  /// the app bar holds in the other themes — "Sender verwalten", the
  /// favourites filter and their order, and reloading the guide. There is no
  /// tab row and no app bar for them; without "Sender verwalten" a hidden
  /// group could never be shown again. The groups are not here — they are the
  /// column LEFT of the channels.
  @override
  OckerRailMenu? get ockerRailMenu => OckerRailMenu.fromEntries(_ockerMenuEntries(), _onOckerMenuChosen);

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
    // ask, so it reads its guide again itself — the guide only, while the one
    // on screen stays (Plebz).
    final iptv = context.read<IptvSourcesProvider?>();
    final hasServers = context.read<MultiServerProvider>().liveTvServers.isNotEmpty;
    if (iptv != null) unawaited(_refreshIptvGuides(iptv, announce: !hasServers));
    await _broadcastToDvrs(
      actionLabel: 'Reload guide',
      successMessage: t.liveTv.guideReloadRequested,
      failureMessage: t.liveTv.guideReloadFailed,
      action: (dvr, serverInfo) => dvr.reloadGuide(serverInfo.dvrKey),
    );
    // The servers' channels are asked for again; with IPTV alone there is
    // nothing to ask, and reloading would only blank the guide on screen.
    if (hasServers) await _loadChannels();
  }

  /// The IPTV half of "TV-Programm neu laden": every source reads its guide
  /// again in the background, the grid keeps the one it shows, and takes the
  /// new one when it is whole. [announce] says so where no server's own
  /// message will.
  Future<void> _refreshIptvGuides(IptvSourcesProvider iptv, {required bool announce}) async {
    await iptv.ensureLoaded();
    if (!mounted || iptv.liveTvSources.isEmpty) return;
    if (announce) showSnackBar(context, t.liveTv.guideReloadRequested);
    final read = await iptv.refreshGuides();
    if (!mounted) return;
    if (read) {
      _guideTabKey.currentState?.reloadPrograms();
    } else {
      showSnackBar(context, t.liveTv.guideReloadFailed, type: SnackBarType.error);
    }
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

  /// Back from a player started on the home screen: the guide takes focus
  /// where the hand-off put its cursor, not on its first channel as an
  /// arrival would.
  @override
  void focusAfterBackgroundSelect() {
    final guide = _currentTab == LiveTvTab.guide ? _guideTabKey.currentState : null;
    if (guide != null) {
      guide.resumeFocus();
    } else {
      _focusCurrentTab();
    }
  }

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
                onChannelMenu: _showChannelMenu,
                takePendingChannel: _takePendingChannel,
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
