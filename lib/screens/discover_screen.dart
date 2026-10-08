import 'dart:async';
import '../media/ids.dart';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:plezy/widgets/app_icon.dart';
import '../widgets/server_activities_button.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'sport/sport_match_sheet.dart';
import 'sport/sport_broadcast_finder.dart';
import 'live_now/live_now_tile.dart';
import 'live_now/live_now_loader.dart';
import '../utils/live_tv_player_navigation.dart';
import '../utils/live_tv_matching.dart';
import '../services/live_tv_last_selection.dart';
import '../navigation/navigation_tabs.dart';
import '../services/sport/sport_repository.dart';
import '../services/sport/sport_models.dart';
import '../services/sport/sport_broadcast_matching.dart';
import '../providers/iptv_sources_provider.dart';
import '../models/livetv_channel.dart';
import 'package:clock/clock.dart';
import 'package:provider/provider.dart';
import '../focus/focusable_action_bar.dart';
import '../focus/hub_vertical_navigation.dart';
import '../focus/locked_hub_controller.dart';
import '../focus/input_mode_tracker.dart';
import '../focus/key_event_utils.dart';

import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_server_client.dart';
import '../media/media_hub.dart';
import '../utils/media_image_helper.dart';
import '../utils/content_utils.dart';
import '../widgets/cycling_media_backdrop.dart';
import '../widgets/optimized_media_image.dart' show ClearLogoImage, blurArtwork;
import '../widgets/toolbar_scrim.dart';
import '../widgets/system_clock.dart';
import '../providers/discover_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/watch_state_store.dart';
import '../widgets/hub_section.dart';
import '../widgets/app_menu.dart';
import '../widgets/clickable_cursor.dart';
import '../widgets/loading_indicator_box.dart';
import '../widgets/profile_switching_overlay.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/profile_avatar.dart';
import '../profiles/profile_menu.dart';
import '../services/settings_service.dart';
import '../widgets/settings_builder.dart';
import '../widgets/fitting_title_text.dart';
import '../widgets/tv_browse_rail.dart';
import '../widgets/tv_spotlight_scaffold.dart';
import '../mixins/refreshable.dart';
import '../mixins/tab_visibility_aware.dart';
import '../i18n/strings.g.dart';
import '../utils/app_logger.dart';
import '../utils/formatters.dart';
import '../utils/hub_icons.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/provider_extensions.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/media_context_menu.dart' show MediaMenuExtraEntry;
import '../utils/video_player_navigation.dart';
import '../utils/layout_constants.dart';
import '../utils/platform_detector.dart';
import '../utils/tone_mapped_logo_image.dart';
import '../theme/mono_tokens.dart';
import 'libraries/content_state_builder.dart';
import 'libraries/state_messages.dart';
import 'main_screen.dart';
import '../navigation/settings_shortcut.dart';
import '../watch_together/watch_together.dart';
import '../providers/companion_remote_provider.dart';
import '../widgets/companion_remote/remote_session_dialog.dart';
import 'companion_remote/mobile_remote_screen.dart';
import '../redesign/ocker_filter_glyph.dart';
import '../redesign/ocker_header_slot.dart';
import '../redesign/ocker_skin.dart';
import '../utils/fork_identity.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with Refreshable, ManualRefreshable, FullRefreshable, TabVisibilityAware, FocusableTab, WidgetsBindingObserver {
  static const Duration _heroAutoScrollDuration = Duration(seconds: 8);
  static const Duration _indicatorUpdateInterval = Duration(milliseconds: 200);

  /// Data + refresh policy live in [DiscoverProvider]; this state keeps only
  /// UI concerns (hero carousel, focus, spotlight). The proxy getters keep
  /// the build code reading naturally.
  late final DiscoverProvider _discover;
  int _seenLoadGeneration = 0;

  List<MediaItem> get _onDeck => _discover.onDeck;
  List<MediaHub> get _hubs => _discover.hubs;
  bool get _hasMoreContinueWatching => _discover.hasMoreContinueWatching;
  bool get _isLoading => _discover.isLoading;
  bool get _areHubsLoading => _discover.areHubsLoading;
  String? get _errorMessage => _discover.errorMessage == null ? null : t.errors.unableToLoad(context: t.discover.title);

  /// A switch begun from the profile menu — here or from the rail's foot.
  bool get _switchingProfile => ProfileMenu.switching.value;

  void _onProfileSwitching() {
    if (mounted) setState(() {});
  }

  final PageController _heroController = PageController();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<int> _heroIndex = ValueNotifier<int>(0);
  Timer? _autoScrollTimer;
  Timer? _indicatorTimer;
  final ValueNotifier<double> _indicatorProgress = ValueNotifier(0.0);
  bool _isAutoScrollPaused = false;
  bool _heroFocusPausedAutoScroll = false;
  final TvSpotlightController _spotlight = TvSpotlightController();
  bool _isTabVisible = true;

  bool _initialLoadComplete = false;
  bool _pendingTvBrowseRailFocus = false;

  /// Primary focus when the rail claim was armed; see [_railClaimAbandoned].
  FocusNode? _railClaimFocusOrigin;

  GlobalKey<HubSectionState>? _continueWatchingHubKey;
  final Map<String, GlobalKey<HubSectionState>> _hubKeysByIdentity = {};
  List<GlobalKey<HubSectionState>> _orderedHubKeys = const [];
  final _tvBrowseRailKey = GlobalKey<TvBrowseRailState>();
  final _hubFocusMemory = HubFocusMemory();

  late FocusNode _heroFocusNode;
  final _actionBarKey = GlobalKey<FocusableActionBarState>();
  final _serverActivitiesButtonKey = GlobalKey<ServerActivitiesButtonState>();
  final _userMenuKey = GlobalKey<AppMenuButtonState<String>>();

  /// Backend-neutral hero client lookup. Returns the actual
  /// [MediaServerClient] for the item's server (Plex or Jellyfin) so
  /// [MediaImageHelper] uses the right transcoder for sized URLs.
  MediaServerClient? _getMediaClientForItem(MediaItem? item) {
    final serverId = item?.serverId;
    if (serverId == null) {
      return context.tryGetMediaClientForServer(null);
    }
    return context.tryGetMediaClientForServer(ServerId(serverId));
  }

  String _hubIdentity(MediaHub hub) => '${hub.serverId ?? ''}:${hub.identifier ?? hub.id}';

  /// Rebuild the per-hub focus keys, keyed by hub *identity* rather than
  /// list position so a row's focus memory follows it when the provider
  /// re-sorts hubs (library-order change). Existing keys are reused to avoid
  /// mass deep unmounts (ARM32 stack overflow during finalizeTree);
  /// duplicate identities get positional suffixes so two rows can never
  /// share a GlobalKey.
  void _updateHubKeys() {
    final occurrences = <String, int>{};
    final liveIdentities = <String>{};
    final ordered = <GlobalKey<HubSectionState>>[];
    for (final hub in _hubs) {
      var identity = _hubIdentity(hub);
      final occurrence = occurrences.update(identity, (n) => n + 1, ifAbsent: () => 0);
      if (occurrence > 0) identity = '$identity#$occurrence';
      liveIdentities.add(identity);
      ordered.add(_hubKeysByIdentity.putIfAbsent(identity, GlobalKey<HubSectionState>.new));
    }
    _hubKeysByIdentity.removeWhere((identity, _) => !liveIdentities.contains(identity));
    _orderedHubKeys = ordered;
    _continueWatchingHubKey ??= GlobalKey<HubSectionState>();
  }

  List<GlobalKey<HubSectionState>> get _allHubKeys {
    final keys = <GlobalKey<HubSectionState>>[];
    if (_continueWatchingHubKey != null && _onDeck.isNotEmpty) {
      keys.add(_continueWatchingHubKey!);
    }
    if (_liveNowHub != null) keys.add(_liveNowHubKey);
    keys.addAll(_orderedHubKeys);
    return keys;
  }

  bool get _isHeroSectionVisible => _onDeck.isNotEmpty && context.settingsRead(SettingsService.showHeroSection);

  // Memoized on provider list identity (the provider always replaces _onDeck/
  // _hubs with fresh instances on change, never mutates in place) so unrelated
  // rebuilds hand TvBrowseRail the same hubs list and its didUpdateWidget
  // fast path — and the cached rail widget below — kick in.
  List<MediaHub>? _tvBrowseHubsCache;
  (List<MediaItem>, List<MediaHub>, bool, String, MediaHub?)? _tvBrowseHubsCacheKey;

  List<MediaHub> get _tvBrowseHubs {
    final key = (_onDeck, _hubs, _hasMoreContinueWatching, t.discover.continueWatching, _liveNowHub);
    if (_tvBrowseHubsCache != null && key == _tvBrowseHubsCacheKey) return _tvBrowseHubsCache!;
    final hubs = <MediaHub>[];
    if (_onDeck.isNotEmpty) {
      hubs.add(_continueWatchingHub);
    }
    if (_liveNowHub case final live?) hubs.add(live);
    hubs.addAll(_hubs.where((hub) => hub.items.isNotEmpty));
    _tvBrowseHubsCache = hubs;
    _tvBrowseHubsCacheKey = key;
    return hubs;
  }

  /// The synthesized Continue Watching row, rendered ahead of the backend hubs
  /// on both the mobile list and the TV rail.
  MediaHub get _continueWatchingHub => MediaHub(
    id: 'continue_watching',
    title: t.discover.continueWatching,
    type: 'mixed',
    identifier: '_continue_watching_',
    size: _onDeck.length + (_hasMoreContinueWatching ? 1 : 0),
    more: _hasMoreContinueWatching,
    items: _onDeck,
  );

  // ---------- Recommendation feedback ----------

  /// "Mehr davon" and "Weniger davon" at the top of a card's menu in the
  /// recommendation row, and nowhere else.
  List<MediaMenuExtraEntry> _recommendationMenuEntries(MediaHub hub, MediaItem item) {
    if (hub.id != recommendationsHubId) return const [];
    final title = item.displayTitle;
    return [
      MediaMenuExtraEntry(
        icon: Symbols.thumb_up_rounded,
        label: t.discover.moreOfThis,
        onSelected: () {
          unawaited(_discover.moreLikeThis(item));
          showSuccessSnackBar(context, t.discover.moreOfThisDone(title: title));
        },
      ),
      MediaMenuExtraEntry(
        icon: Symbols.thumb_down_rounded,
        label: t.discover.lessOfThis,
        onSelected: () {
          unawaited(_discover.lessLikeThis(item));
          showSuccessSnackBar(context, t.discover.lessOfThisDone(title: title));
        },
      ),
    ];
  }

  // ---------- "Jetzt live" ----------

  LiveNowLoader? _liveNowLoader;
  SportBroadcastFinder? _liveNowFinder;
  LiveNowSnapshot _liveNow = LiveNowSnapshot.empty;
  Timer? _liveNowTimer;
  bool _liveNowOpening = false;
  final _liveNowHubKey = GlobalKey<HubSectionState>();

  /// The row's hub, replaced only when what a tile *says* changes — an entry
  /// coming or going, a score, the next programme. Between those the tiles
  /// redraw from [LiveNowScope] alone, so a minute's refresh neither rebuilds
  /// the rail nor moves the cursor on it.
  MediaHub? _liveNowHubCache;
  String _liveNowSignature = '';

  MediaHub? get _liveNowHub => _liveNow.isEmpty ? null : _liveNowHubCache;

  /// The row's switch in the settings; off, nothing behind the row is loaded.
  ValueListenable<bool>? _showLiveNowListenable;

  bool get _liveNowWanted => SettingsService.instanceOrNull?.read(SettingsService.showLiveNowRow) ?? true;

  void _startLiveNow() {
    final multiServer = context.read<MultiServerProvider?>();
    final finder = SportBroadcastFinder.maybeOf(context);
    if (multiServer == null || finder == null) return;
    _liveNowFinder = finder;
    _liveNowLoader = LiveNowLoader(
      multiServer: multiServer,
      finder: finder,
      iptv: context.read<IptvSourcesProvider?>(),
      sportEnabled: () => SettingsService.instanceOrNull?.read(SettingsService.showSportTab) ?? false,
    );
    _showLiveNowListenable = SettingsService.instanceOrNull?.listenable(SettingsService.showLiveNowRow);
    _showLiveNowListenable?.addListener(_onShowLiveNowChanged);
    _resumeLiveNow();
  }

  void _onShowLiveNowChanged() {
    if (!mounted) return;
    if (_liveNowWanted) {
      _resumeLiveNow();
    } else {
      _liveNowTimer?.cancel();
      _liveNowTimer = null;
      setState(() {
        _liveNow = LiveNowSnapshot.empty;
        _liveNowHubCache = null;
        _liveNowSignature = '';
      });
    }
  }

  void _resumeLiveNow() {
    if (_liveNowLoader == null || _liveNowTimer != null || !_liveNowWanted) return;
    unawaited(_refreshLiveNow());
    // A live score moves by the minute; the loader asks each source only as
    // often as that source can have changed.
    _liveNowTimer = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(_refreshLiveNow()));
  }

  Future<void> _refreshLiveNow() async {
    final loader = _liveNowLoader;
    if (loader == null) return;
    final LiveNowSnapshot snapshot;
    try {
      snapshot = await loader.load();
    } catch (error, stackTrace) {
      appLogger.d('Live now: refresh failed', error: error, stackTrace: stackTrace);
      return;
    }
    // Switched off while the load was under way.
    if (!mounted || !_liveNowWanted) return;
    final hub = liveNowHub(snapshot);
    final signature = [for (final item in hub.items) '${item.id}|${item.title}|${item.summary}'].join('\n');
    setState(() {
      _liveNow = snapshot;
      if (signature != _liveNowSignature) {
        _liveNowSignature = signature;
        _liveNowHubCache = hub;
      }
    });
  }

  /// A channel tunes. A game on now tunes the channel the guide has it on,
  /// and opens its window where the guide has nothing — as does a game still
  /// to come, whose window names where it will be on.
  Future<void> _openLiveNow(MediaItem item) async {
    if (_liveNowOpening) return;
    final multiServer = context.read<MultiServerProvider?>();
    switch (_liveNow.byId[item.id]) {
      case LiveNowChannel(:final channel):
        if (multiServer == null) return;
        _handLiveTvOff(channel);
        await navigateToLiveTv(
          context,
          multiServer: multiServer,
          channel: channel,
          channels: _liveNow.channels,
          group: liveTvNonEmpty(channel.lineup),
        );
      case LiveNowGame(:final match, :final league):
        _liveNowOpening = true;
        try {
          await _openLiveNowGame(match, league, multiServer);
        } finally {
          _liveNowOpening = false;
        }
      case null:
        return;
    }
  }

  /// Behind the player about to open, Live TV comes forward on [channel]'s
  /// group with the channel under the cursor: closing the player lands in the
  /// guide, where the viewer can zap on, not back on the home screen.
  void _handLiveTvOff(LiveTvChannel channel) {
    LiveTvLastSelection.instance.handOff(
      channelKey: liveTvChannelScopeKey(channel),
      group: liveTvNonEmpty(channel.lineup),
    );
    MainScreenTabSwitcher.selectTabOf(context, NavigationTabId.liveTv);
  }

  Future<void> _openLiveNowGame(SportMatch match, SportLeague league, MultiServerProvider? multiServer) async {
    void watch(SportBroadcast broadcast, List<LiveTvChannel> channels, {int? startAtEpoch}) {
      if (multiServer == null || !mounted) return;
      _handLiveTvOff(broadcast.channel);
      unawaited(
        navigateToLiveTv(
          context,
          multiServer: multiServer,
          channel: broadcast.channel,
          channels: channels,
          startAtEpoch: startAtEpoch,
          group: liveTvNonEmpty(broadcast.channel.lineup),
        ),
      );
    }

    final search = _liveNowFinder?.search(match, league);
    if (match.isLive(clock.now()) && search != null) {
      final found = await search;
      if (!mounted) return;
      final broadcast = found?.broadcasts.firstOrNull;
      if (found != null && broadcast != null) {
        watch(broadcast, found.channels);
        return;
      }
    }
    final table = await SportRepository.instance.table(league, match.season);
    if (!mounted) return;
    await showSportMatchSheet(
      context,
      match: match,
      league: league,
      table: table ?? const <SportTableRow>[],
      broadcasts: search,
      onWatch: watch,
    );
  }

  void _setSpotlightItem(MediaItem item) => _spotlight.select(item);

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _focusTopActions() {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    // Under the redesign the same actions stand in the top right corner of
    // the screen (see [OckerRailShell]), and UP reaches them as it reaches
    // the standard theme's toolbar.
    final actionBar = _actionBarKey.currentState;
    if (actionBar != null) {
      actionBar.requestFocusOnFirst();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
      _actionBarKey.currentState?.requestFocusOnFirst();
    });
  }

  void _focusTopBoundary() {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    if (PlatformDetector.isTV()) {
      _focusTopActions();
    } else if (_isHeroSectionVisible) {
      _heroFocusNode.requestFocus();
    } else {
      _focusTopActions();
    }
    _scrollToTop();
  }

  void _focusContentFromAppBar() {
    if (PlatformDetector.isTV()) {
      _focusTvBrowseRailWhenReady(immediate: true);
      return;
    }

    if (_isHeroSectionVisible) {
      _heroFocusNode.requestFocus();
      return;
    }

    final keys = _allHubKeys;
    if (keys.isNotEmpty) {
      keys.first.currentState?.requestFocusFromMemory();
    }
  }

  void _focusTvBrowseRailWhenReady({bool immediate = false}) {
    if (!PlatformDetector.isTV()) return;
    if (!_isTabVisible || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      _pendingTvBrowseRailFocus = false;
      return;
    }

    _pendingTvBrowseRailFocus = true;
    _railClaimFocusOrigin = FocusManager.instance.primaryFocus;
    if (immediate && _tvBrowseHubs.isNotEmpty) {
      final rail = _tvBrowseRailKey.currentState;
      if (rail != null) {
        _pendingTvBrowseRailFocus = false;
        rail.requestFocus();
        return;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_isTabVisible || !(ModalRoute.of(context)?.isCurrent ?? false)) {
        _pendingTvBrowseRailFocus = false;
        return;
      }
      if (_tvBrowseHubs.isEmpty) return;
      final rail = _tvBrowseRailKey.currentState;
      if (rail == null) return;
      _pendingTvBrowseRailFocus = false;
      rail.requestFocus();
    });
  }

  /// A rail-focus request stays armed while the rail has no hubs to focus
  /// (empty first load), so hubs landing later still receive it. It must not
  /// outlive the user's own navigation: hubs arriving minutes later would
  /// yank the remote off a sidebar item the user has since moved to.
  ///
  /// Where focus *sits* cannot tell those apart — MainScreen hands a tab over
  /// while focus is still on the sidebar item that selected it, and that
  /// request is as live as one made from a bare scope. What distinguishes a
  /// stale claim is that focus *moved* after the request was armed and now
  /// rests on a control off this screen. A bare scope — MainScreen's content
  /// scope before any child has focus — is "nowhere yet", not a destination.
  bool get _railClaimAbandoned {
    final node = FocusManager.instance.primaryFocus;
    if (identical(node, _railClaimFocusOrigin)) return false;
    final focusContext = node?.context;
    if (node == null || node is FocusScopeNode || focusContext == null) return false;
    return !identical(focusContext.findAncestorStateOfType<_DiscoverScreenState>(), this);
  }

  void _applyPendingTvBrowseRailFocus() {
    if (!_pendingTvBrowseRailFocus) return;
    if (_railClaimAbandoned) {
      _pendingTvBrowseRailFocus = false;
      return;
    }
    _focusTvBrowseRailWhenReady();
  }

  /// Handle vertical navigation between hubs
  /// Returns true if the navigation was handled
  /// Rows the app puts above the server's hubs: Continue Watching and
  /// "Jetzt live", where they have anything to show.
  int get _rowsAboveHubs => (_onDeck.isNotEmpty ? 1 : 0) + (_liveNowHub != null ? 1 : 0);

  bool _handleVerticalNavigation(int hubIndex, bool isUp) {
    final keys = _allHubKeys;
    return navigateVerticalHubRows(
      hubCount: keys.length,
      hubIndex: hubIndex,
      isUp: isUp,
      onTopBoundary: _focusTopBoundary,
      requestFocus: (targetIndex) {
        keys[targetIndex].currentState?.requestFocusFromMemory();
      },
    );
  }

  void _navigateToSidebar() {
    MainScreenFocusScope.focusSidebarOf(context);
  }

  @override
  void initState() {
    super.initState();
    ProfileMenu.switching.addListener(_onProfileSwitching);
    WidgetsBinding.instance.addObserver(this);
    _heroFocusNode = FocusNode(debugLabel: 'hero_section');
    _heroFocusNode.addListener(_onHeroFocusChanged);
    _discover = context.read<DiscoverProvider>();
    _seenLoadGeneration = _discover.loadGeneration;
    _discover.addListener(_onDiscoverChanged);
    _updateHubKeys();
    unawaited(_discover.load());
    _startAutoScroll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startLiveNow();
    });
  }

  /// Mirror provider changes into this state's UI concerns: rebuild, apply
  /// pending TV-rail focus, and keep the hero carousel index in sync — a
  /// fresh [DiscoverProvider.load] resets it, a background Continue Watching
  /// refresh only clamps it.
  /// Everything the build reads from the provider (list identities — the
  /// provider replaces lists on change — plus the scalar flags). Notifies
  /// that leave this unchanged (e.g. a watch-state-driven Continue Watching
  /// refresh that found nothing new) skip the setState so the whole screen —
  /// TV rail included — is not rebuilt for nothing.
  (List<MediaItem>, List<MediaHub>, bool, bool, bool, String?) get _renderSignature =>
      (_onDeck, _hubs, _hasMoreContinueWatching, _isLoading, _areHubsLoading, _discover.errorMessage);

  (List<MediaItem>, List<MediaHub>, bool, bool, bool, String?)? _seenRenderSignature;

  void _onDiscoverChanged() {
    if (!mounted) return;
    final generation = _discover.loadGeneration;
    final isNewLoad = generation != _seenLoadGeneration;
    _seenLoadGeneration = generation;
    final heroOutOfBounds = _heroIndex.value >= _onDeck.length;
    final signature = _renderSignature;
    final renderChanged = isNewLoad || heroOutOfBounds || signature != _seenRenderSignature;
    _seenRenderSignature = signature;

    if (renderChanged) {
      setState(() {
        if (isNewLoad || heroOutOfBounds) _heroIndex.value = 0;
        _updateHubKeys();
      });
    }
    _applyPendingTvBrowseRailFocus();

    if ((isNewLoad || heroOutOfBounds) && _heroController.hasClients && _onDeck.isNotEmpty) {
      _heroController.jumpToPage(0);
    }
    // Focus hero when fresh content lands, but only if no modal route is on top
    if (isNewLoad && !PlatformDetector.isTV() && _onDeck.isNotEmpty && (ModalRoute.of(context)?.isCurrent ?? false)) {
      _heroFocusNode.requestFocus();
    }

    // On initial load, focus content so the user doesn't start on the toolbar
    if (!_initialLoadComplete) {
      if (PlatformDetector.isTV() && (_onDeck.isNotEmpty || _hubs.isNotEmpty)) {
        _initialLoadComplete = true;
        _focusTvBrowseRailWhenReady();
      } else if (!PlatformDetector.isTV() && _onDeck.isNotEmpty) {
        _initialLoadComplete = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
          if (_heroFocusNode.canRequestFocus) {
            _heroFocusNode.requestFocus();
          }
        });
      }
    }
  }

  void _onHeroFocusChanged() {
    if (!PlatformDetector.isTV()) return;

    if (_heroFocusNode.hasFocus) {
      _heroFocusPausedAutoScroll = true;
      _autoScrollTimer?.cancel();
      _stopIndicatorProgress();
      return;
    }

    if (_heroFocusPausedAutoScroll) {
      _heroFocusPausedAutoScroll = false;
      if (_isTabVisible && !_isAutoScrollPaused) _startAutoScroll();
    }
  }

  /// Handle key events for the hero section.
  KeyEventResult _handleHeroKeyEvent(FocusNode node, KeyEvent event) {
    final backResult = handleBackKeyAction(event, _navigateToSidebar);
    if (backResult != KeyEventResult.ignored) return backResult;

    return dpadKeyHandler(
      onDown: () {
        final keys = _allHubKeys;
        if (keys.isNotEmpty) keys.first.currentState?.requestFocusFromMemory();
      },
      onUp: _focusTopActions,
      onLeft: () {
        if (_heroIndex.value > 0) {
          _heroController.previousPage(duration: tokens(context).slow, curve: Curves.easeInOut);
        } else {
          _navigateToSidebar();
        }
      },
      onRight: () {
        if (_heroIndex.value < _onDeck.length - 1) {
          _heroController.nextPage(duration: tokens(context).slow, curve: Curves.easeInOut);
        }
      },
      onSelect: () {
        final heroIndex = _heroIndex.value;
        if (_onDeck.isNotEmpty && heroIndex < _onDeck.length) {
          navigateToMediaItem(context, _onDeck[heroIndex], playDirectly: true);
        }
      },
    )(node, event);
  }

  @override
  void dispose() {
    ProfileMenu.switching.removeListener(_onProfileSwitching);
    _discover.removeListener(_onDiscoverChanged);
    WidgetsBinding.instance.removeObserver(this);
    // The rotation belongs to this screen's time on show, not to the
    // provider's lifetime — it outlives this widget.
    _discover.watchRecommendationsRotation(false);
    _autoScrollTimer?.cancel();
    _indicatorTimer?.cancel();
    _liveNowTimer?.cancel();
    _showLiveNowListenable?.removeListener(_onShowLiveNowChanged);
    _spotlight.dispose();
    _indicatorProgress.dispose();
    _heroIndex.dispose();
    _heroController.dispose();
    _scrollController.dispose();
    _heroFocusNode.removeListener(_onHeroFocusChanged);
    _heroFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Restart auto-scroll only if discover tab is visible
      if (_isTabVisible && !_isAutoScrollPaused) _startAutoScroll();
      // Stale hubs refetch on every resume — cheap timestamp check, and a
      // desktop window-focus gain after hours away should refresh too (#1646).
      final startedFullPass = _discover.refreshIfStale();
      // Refresh continue watching on mobile only
      // (on desktop, "resumed" fires on every window focus gain)
      if (!startedFullPass && (Platform.isIOS || Platform.isAndroid)) {
        unawaited(_discover.refreshContinueWatching());
      }
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      // Stop animations to prevent scroll state corruption while backgrounded
      _autoScrollTimer?.cancel();
      _stopIndicatorProgress();
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    if (PlatformDetector.isTV()) return;
    if (_isAutoScrollPaused) return;

    _startIndicatorProgress();
    _autoScrollTimer = Timer.periodic(_heroAutoScrollDuration, (timer) {
      if (_onDeck.isEmpty || !_heroController.hasClients || _isAutoScrollPaused) {
        return;
      }

      // Validate current index is within bounds before calculating next page
      if (_heroIndex.value >= _onDeck.length) _heroIndex.value = 0;

      final nextPage = (_heroIndex.value + 1) % _onDeck.length;
      _heroController.animateToPage(nextPage, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      // Wait for page transition to complete before resetting progress
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_isAutoScrollPaused) {
          _startIndicatorProgress();
        }
      });
    });
  }

  void _startIndicatorProgress() {
    if (!mounted) return;
    _indicatorTimer?.cancel();
    _indicatorProgress.value = 0.0;
    final totalSteps = _heroAutoScrollDuration.inMilliseconds ~/ _indicatorUpdateInterval.inMilliseconds;
    int step = 0;
    _indicatorTimer = Timer.periodic(_indicatorUpdateInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      step++;
      _indicatorProgress.value = (step / totalSteps).clamp(0.0, 1.0);
      if (step >= totalSteps) {
        timer.cancel();
      }
    });
  }

  void _stopIndicatorProgress() {
    _indicatorTimer?.cancel();
  }

  void _resetAutoScrollTimer() {
    _autoScrollTimer?.cancel();
    _startAutoScroll();
  }

  void _pauseAutoScroll() {
    setState(() {
      _isAutoScrollPaused = true;
    });
    _autoScrollTimer?.cancel();
    _stopIndicatorProgress();
  }

  void _resumeAutoScroll() {
    setState(() {
      _isAutoScrollPaused = false;
    });
    _startAutoScroll();
  }

  @override
  void onTabHidden() {
    _isTabVisible = false;
    _pendingTvBrowseRailFocus = false;
    _autoScrollTimer?.cancel();
    _stopIndicatorProgress();
    _discover.watchRecommendationsRotation(false);
  }

  @override
  void onTabShown() {
    _isTabVisible = true;
    _discover.refreshIfStale();
    // A device that slept through a rotation wakes with the row it had and a
    // timer that never fired.
    _discover.refreshRecommendationsIfStale();
    // And while this screen is the one on show, the row turns over on its own.
    _discover.watchRecommendationsRotation(true);
    if (!_isAutoScrollPaused) {
      _startAutoScroll();
    }
  }

  @override
  void focusActiveTabIfReady() {
    if (PlatformDetector.isTV()) {
      _focusTvBrowseRailWhenReady();
      return;
    }
    _focusTopBoundary();
  }

  // Helper method to calculate visible dot range (max 5 dots)
  ({int start, int end}) _getVisibleDotRange() {
    final totalDots = _onDeck.length;
    if (totalDots <= 5) {
      return (start: 0, end: totalDots - 1);
    }

    // Center the active dot when possible
    final center = _heroIndex.value;
    final int start = (center - 2).clamp(0, totalDots - 5);
    final int end = start + 4; // 5 dots total (0-4 inclusive)

    return (start: start, end: end);
  }

  // Helper method to determine dot size based on position
  double _getDotSize(int dotIndex, int start, int end) {
    final totalDots = _onDeck.length;

    // If we have 5 or fewer dots, all are full size (8px)
    if (totalDots <= 5) {
      return 8.0;
    }

    // First and last visible dots are smaller if there are more items beyond them
    final isFirstVisible = dotIndex == start && start > 0;
    final isLastVisible = dotIndex == end && end < totalDots - 1;

    if (isFirstVisible || isLastVisible) {
      return 5.0; // Smaller edge dots
    }

    return 8.0; // Normal size
  }

  @override
  void manualRefresh() => unawaited(_refreshFromToolbar());

  Future<void> _refreshFromToolbar() async {
    final outcome = await _discover.refreshNow();
    if (!mounted) return;
    switch (outcome) {
      case DiscoverRefreshOutcome.failed:
        showErrorSnackBar(context, t.errors.unableToLoad(context: t.discover.title));
      case DiscoverRefreshOutcome.degraded:
        appLogger.w('Discover refresh completed with partial server failures');
      case DiscoverRefreshOutcome.cancelled:
      case DiscoverRefreshOutcome.refreshed:
        break;
    }
  }

  // Public method to refresh content (for normal navigation)
  @override
  void refresh() {
    // A stale-resume refresh must also refetch the home hubs; otherwise new
    // server-side media never appears until a restart (#1646). When fresh,
    // only Continue Watching refetches — one on-deck call, zero hub calls.
    if (_discover.refreshIfStale()) return;
    unawaited(_discover.refreshContinueWatching());
  }

  // Public method to fully reload all content (for profile switches)
  @override
  void fullRefresh() {
    unawaited(_discover.load());
  }

  @override
  void primeRefresh() {
    // `initState` already fired `load()`. On cold start that pass is still
    // running when the online-entry hook primes the tab, and asking again only
    // queues an identical trailing pass — the whole home fan-out twice (#1784).
    // When nothing is in flight (reconnect-from-offline, or a first pass that
    // gave up because no server was online yet) a real refresh is still owed.
    if (_discover.isLoadInFlight) return;
    fullRefresh();
  }

  /// Whether the loaded hubs span more than one connected server.
  bool _hubsSpanMultipleServers() {
    final serverIds = _hubs.where((hub) => hub.serverId != null).map((hub) => hub.serverId).toSet();
    return serverIds.length > 1;
  }

  void _handleOpenSettings(BuildContext context) {
    final mainScope = MainScreenFocusScope.of(context, listen: false);
    if (mainScope != null) {
      mainScope.openSettings?.call();
      return;
    }

    Navigator.push(context, buildSettingsRoute());
  }

  /// Build the [FocusableAction] wrapping the user menu.
  /// Pulls live state from [ActiveProfileProvider]; the menu reuses
  /// [_userMenuItems] for the menu contents so d-pad and tap paths
  /// stay in sync.
  FocusableAction _buildUserMenuAction(BuildContext context) {
    final activeProvider = context.watch<ActiveProfileProvider>();
    final active = activeProvider.active;

    AppMenuButton<String> menu({Widget? icon, Widget? child}) => AppMenuButton<String>(
      key: _userMenuKey,
      enabled: !_switchingProfile,
      icon: icon,
      tooltip: t.profiles.sectionTitle,
      adaptiveSheet: true,
      anchorAlignment: AppMenuAnchorAlignment.end,
      onSelected: (value) =>
          unawaited(ProfileMenu.handle(context, value, openSettings: () => _handleOpenSettings(context))),
      entriesBuilder: ProfileMenu.entries,
      child: child,
    );

    // In the redesign's header this is one outline in a row of outlines, so it
    // is drawn by the very glyph the others are drawn by — same size, same box,
    // same ring, same ink. It used to be an `AppMenuButton` icon, which is an
    // IconButton, which keeps a 48-pixel tap target whatever its glyph
    // measures: beside a 16-pixel refresh in a 34-pixel box it sat half again
    // as large and off the row's centre. Nothing is lost by dropping the
    // button — the menu opens from the enclosing Focus, and the tap path goes
    // through the child branch of [AppMenuButton], which has no padding of its
    // own.
    if (isOckerLayout(context)) {
      return FocusableAction(
        onPressed: _switchingProfile ? null : () => _userMenuKey.currentState?.showButtonMenu(focusFirstItem: true),
        builder: (context, state) => menu(
          child: OckerFilterGlyph(icon: Symbols.account_circle, focused: state.showFocus),
        ),
      );
    }

    return FocusableAction(
      onPressed: _switchingProfile ? null : () => _userMenuKey.currentState?.showButtonMenu(focusFirstItem: true),
      child: menu(
        // The redesign keeps a plain person here instead of the profile's own picture:
        // one glyph among the others in the bar rather than the one thing in it
        // that is a photograph. The menu behind it still names the profiles.
        icon: active != null && tokens(context).profileAvatar
            ? ProfileAvatar(profile: active, size: 32, avatarUrl: activeProvider.avatarUrlFor(active.id))
            : AppIcon(
                tokens(context).profileAvatar ? Symbols.account_circle_rounded : Symbols.account_circle,
                // The redesign lets the theme's own fill and weight through.
                fill: tokens(context).profileAvatar ? 1 : null,
                // 32 is an avatar's size, and reads as a portrait among glyphs.
                size: 32,
                color: isOcker(context) ? tokens(context).ink(0.55) : Colors.white,
              ),
      ),
    );
  }

  /// The screen's own chrome — refresh, profile, whatever the switches allow —
  /// handed to the shell's top right corner under the redesign.
  ///
  /// A stable closure rather than one built per frame: the slot compares what
  /// it is given by identity, and a fresh closure every build would republish
  /// (and rebuild the band) on every frame of a scroll.
  Widget _ockerHeaderChrome(BuildContext _) => _buildToolbarActions(tokens(context).ink(0.55));

  void _publishOckerHeaderChrome() {
    if (!isOckerLayout(context)) return;
    OckerHeaderSlot.publish(context, _ockerHeaderChrome);
  }

  Widget _buildOverlaidAppBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = colorScheme.onSurface;
    return ToolbarScrim(
      child: Row(
        children: [
          if (!PlatformDetector.isTV())
            Text(
              t.discover.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: foregroundColor, fontWeight: .bold),
            ),
          const Spacer(),
          _buildToolbarActions(foregroundColor),
          // TV only: a fullscreen leanback app hides the system clock, while a
          // phone status bar and a desktop menu bar already show one.
          //
          // Outermost on purpose. The buttons beside it can be set to fade out
          // until the remote reaches them, and a clock left of that gap would
          // sit stranded in the middle of the bar.
          if (PlatformDetector.isTV()) ...[
            const SizedBox(width: 12),
            SystemClock(
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: foregroundColor, fontWeight: .w500),
            ),
          ],
        ],
      ),
    );
  }

  /// The actions alone, without the scrim, the screen title or the clock.
  ///
  /// "Ocker" has no backdrop for a toolbar to float over and a header that
  /// already carries a clock, so it takes these on their own and puts them at
  /// the end of the header row. Same widgets, same callbacks, one place.
  Widget _buildToolbarActions(Color foregroundColor) {
    final colorScheme = Theme.of(context).colorScheme;
    return Consumer2<WatchTogetherProvider, CompanionRemoteProvider>(
      builder: (context, watchTogether, companionRemote, _) {
        final isDesktop = PlatformDetector.shouldActAsRemoteHost(context);
        void openWatchTogether() =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchTogetherScreen()));
        void openCompanionRemote() {
          if (isDesktop) {
            RemoteSessionDialog.show(context);
          } else {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const MobileRemoteScreen()));
          }
        }

        // The three optional entry points below are per-feature switches,
        // so the bar rebuilds when any of them is flipped.
        return SettingsBuilder(
          prefs: const [
            SettingsService.showWatchTogetherAction,
            SettingsService.showCompanionRemoteAction,
            SettingsService.showServerActivitiesAction,
          ],
          builder: (context) {
            final settings = SettingsService.instance;
            return FocusableActionBar(
              key: _actionBarKey,
              hideUntilFocused: settings.read(SettingsService.hideHomeActionsUntilFocus),
              onNavigateLeft: _navigateToSidebar,
              onNavigateDown: _focusContentFromAppBar,
              actions: [
                FocusableAction(icon: Symbols.refresh_rounded, iconColor: foregroundColor, onPressed: manualRefresh),
                // Watch Together
                if (watchTogetherAvailable && settings.read(SettingsService.showWatchTogetherAction))
                  FocusableAction(
                    onPressed: openWatchTogether,
                    child: Stack(
                      children: [
                        IconButton(
                          icon: AppIcon(
                            Symbols.group_rounded,
                            fill: watchTogether.isInSession ? 1 : 0,
                            color: watchTogether.isInSession ? colorScheme.primary : foregroundColor,
                          ),
                          onPressed: openWatchTogether,
                          tooltip: t.watchTogether.title,
                        ),
                        if (watchTogether.isInSession && watchTogether.participantCount > 1)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.all(Radius.circular(flatRadius(context, 8))),
                              ),
                              child: Text(
                                '${watchTogether.participantCount}',
                                style: TextStyle(color: colorScheme.onPrimary, fontSize: 10, fontWeight: .bold),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                // Companion Remote
                if (settings.read(SettingsService.showCompanionRemoteAction))
                  FocusableAction(
                    onPressed: openCompanionRemote,
                    child: Stack(
                      children: [
                        IconButton(
                          icon: AppIcon(
                            Symbols.phone_android_rounded,
                            fill: companionRemote.isConnected ? 1 : 0,
                            color: companionRemote.isConnected ? colorScheme.primary : foregroundColor,
                          ),
                          onPressed: openCompanionRemote,
                          tooltip: t.companionRemote.title,
                        ),
                        if (companionRemote.isConnected)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border: Border.fromBorderSide(BorderSide(color: foregroundColor, width: 1)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                // Server Tasks — Plex-only (`/activities` API has no
                // Jellyfin equivalent), hide the button entirely on
                // Jellyfin-only profiles so the chrome doesn't show
                // a permanently empty popover.
                if (settings.read(SettingsService.showServerActivitiesAction) &&
                    PlatformDetector.isDesktop(context) &&
                    context.select<MultiServerProvider, bool>((p) => p.hasOnlinePlexServers))
                  FocusableAction(
                    onPressed: () => _serverActivitiesButtonKey.currentState?.togglePanel(),
                    child: ServerActivitiesButton(key: _serverActivitiesButtonKey),
                  ),
                // User menu — profiles + sign out. Under "Flach" on a
                // television it lives at the rail's foot instead (Plebz).
                if (!(isOckerLayout(context) && ockerFlat(context))) _buildUserMenuAction(context),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsBuilder(
      prefs: const [
        SettingsService.showServerNameOnHubs,
        SettingsService.showHeroSection,
        SettingsService.hideSpoilers,
        SettingsService.libraryDensity,
        SettingsService.episodePosterMode,
      ],
      builder: (context) => LiveNowScope(snapshot: _liveNow, child: _buildContent(context)),
    );
  }

  Widget _buildContent(BuildContext context) {
    final svc = SettingsService.instance;
    final showHeroSection = svc.read(SettingsService.showHeroSection);

    if (PlatformDetector.isTV()) {
      return _buildTvContent(context);
    }

    final showServerNameOnHubs = svc.read(SettingsService.showServerNameOnHubs);
    final hubsSpanMultipleServers = _hubsSpanMultipleServers();

    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final theme = Theme.of(context);
    final continueWatchingHub = _onDeck.isEmpty ? null : _continueWatchingHub;
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Hero Section (Continue Watching) - at top of screen
              Builder(
                builder: (context) {
                  if (_onDeck.isNotEmpty && showHeroSection) {
                    return _buildHeroSection();
                  }
                  // Add top padding when hero is not shown
                  return SliverToBoxAdapter(
                    child: SizedBox(height: kToolbarHeight + MediaQuery.paddingOf(context).top + 16),
                  );
                },
              ),
              if (_isLoading) LoadingIndicatorBox.sliver,
              if (_errorMessage != null) SliverErrorState(message: _errorMessage!, onRetry: _discover.load),
              if (!_isLoading && _errorMessage == null) ...[
                if (continueWatchingHub != null)
                  SliverToBoxAdapter(
                    child: HubSection(
                      key: _continueWatchingHubKey,
                      hub: continueWatchingHub,
                      focusMemory: _hubFocusMemory,
                      icon: hubIconFor(continueWatchingHub),
                      onRefresh: _discover.updateItem,
                      onRemoveFromContinueWatching: _discover.refreshContinueWatching,
                      isInContinueWatching: true,
                      loadMoreItems: _discover.loadAllContinueWatching,
                      onVerticalNavigation: (isUp) => _handleVerticalNavigation(0, isUp),
                      onNavigateUp: _focusTopBoundary,
                      onNavigateToSidebar: _navigateToSidebar,
                    ),
                  ),

                // "Jetzt live": today's games, then the favourite channels.
                if (_liveNowHub case final liveHub?)
                  SliverToBoxAdapter(
                    child: HubSection(
                      key: _liveNowHubKey,
                      hub: liveHub,
                      focusMemory: _hubFocusMemory,
                      icon: Symbols.live_tv_rounded,
                      onItemTap: (item) => unawaited(_openLiveNow(item)),
                      onVerticalNavigation: (isUp) => _handleVerticalNavigation(_onDeck.isNotEmpty ? 1 : 0, isUp),
                      onNavigateUp: _onDeck.isEmpty ? _focusTopBoundary : null,
                      onNavigateToSidebar: _navigateToSidebar,
                    ),
                  ),

                // Recommendation Hubs (Trending, Top in Genre, etc.)
                for (int i = 0; i < _hubs.length; i++)
                  SliverToBoxAdapter(
                    child: HubSection(
                      key: i < _orderedHubKeys.length ? _orderedHubKeys[i] : null,
                      hub: _hubs[i],
                      focusMemory: _hubFocusMemory,
                      icon: hubIconFor(_hubs[i]),
                      showServerName: showServerNameOnHubs || hubsSpanMultipleServers,
                      onRefresh: _discover.updateItem,
                      // Hub index is i + 1 if continue watching exists, otherwise i
                      onVerticalNavigation: (isUp) => _handleVerticalNavigation(_rowsAboveHubs + i, isUp),
                      onNavigateUp: (i == 0 && _rowsAboveHubs == 0) ? _focusTopBoundary : null,
                      onNavigateToSidebar: _navigateToSidebar,
                      menuLeadingEntriesFor: _hubs[i].id == recommendationsHubId
                          ? (item) => _recommendationMenuEntries(_hubs[i], item)
                          : null,
                    ),
                  ),

                // Show loading skeleton for hubs while they're loading
                if (_areHubsLoading && _hubs.isEmpty)
                  for (int i = 0; i < 3; i++)
                    SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: .start,
                          children: [
                            Container(
                              width: 200,
                              height: 24,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.all(Radius.circular(flatRadius(context, 4))),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 200,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: 5,
                                itemBuilder: (context, index) {
                                  return Container(
                                    margin: const EdgeInsets.only(right: 12),
                                    width: 140,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(tokens(context).radiusSm),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                if (_onDeck.isEmpty && _hubs.isEmpty && !_areHubsLoading)
                  SliverEmptyState(
                    message: t.discover.noContentAvailable,
                    subtitle: t.discover.addMediaToLibraries,
                    icon: Symbols.movie_rounded,
                  ),

                SliverToBoxAdapter(child: SizedBox(height: 24 + bottomPadding)),
              ],
            ],
          ),
          // Overlaid app bar — excluded from default focus traversal so that
          // initial/tab-switch focus lands on content (hero/hubs), not the toolbar.
          // Toolbar buttons are still reachable via explicit UP from hero section.
          Positioned(top: 0, left: 0, right: 0, child: ExcludeFocusTraversal(child: _buildOverlaidAppBar())),
          if (_switchingProfile) const ProfileSwitchingOverlay(),
        ],
      ),
    );
  }

  // Cached so unrelated _buildTvContent rebuilds (loading flags, spotlight
  // geometry) hand Element.updateChild the identical widget instance and the
  // whole rail subtree is skipped. Rebuilt only when its actual inputs change.
  TvBrowseRail? _tvBrowseRailWidget;
  (List<MediaHub>, bool)? _tvBrowseRailWidgetKey;

  Widget _cachedTvBrowseRail(List<MediaHub> browseHubs, {required bool showServerName}) {
    final key = (browseHubs, showServerName);
    if (_tvBrowseRailWidget != null && key == _tvBrowseRailWidgetKey) return _tvBrowseRailWidget!;
    _tvBrowseRailWidgetKey = key;
    return _tvBrowseRailWidget = TvBrowseRail(
      key: _tvBrowseRailKey,
      hubs: browseHubs,
      initialHubId: 'continue_watching',
      focusMemory: _hubFocusMemory,
      showServerName: showServerName,
      iconForHub: (hub, _) => hubIconFor(hub),
      onFocusedItemChanged: _setSpotlightItem,
      onRefresh: _discover.updateItem,
      onRemoveFromContinueWatching: _discover.refreshContinueWatching,
      isContinueWatchingHub: (hub) => hub.isContinueWatchingHub,
      usesContinueWatchingAction: (hub) => hub.usesContinueWatchingAction,
      // Only for the hubs the rail cannot page from a server: Continue
      // Watching is assembled here, across servers, so it is handed over
      // whole. Everything else is read a page at a time — see
      // TvBrowseRail._navigateToHubDetail.
      loadMoreItems: (hub) => hub.id == 'continue_watching' ? _discover.loadAllContinueWatching : null,
      // A "Jetzt live" tile tunes or opens a game rather than a detail page.
      onActivateItem: (hub, item) {
        if (hub.id != liveNowHubId) return false;
        unawaited(_openLiveNow(item));
        return true;
      },
      onNavigateUp: _focusTopActions,
      onNavigateToSidebar: _navigateToSidebar,
      tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
      menuLeadingEntriesFor: _recommendationMenuEntries,
    );
  }

  Widget _buildTvContent(BuildContext context) {
    _publishOckerHeaderChrome();
    final svc = SettingsService.instance;
    final hideSpoilers = svc.read(SettingsService.hideSpoilers);
    final showServerNameOnHubs = svc.read(SettingsService.showServerNameOnHubs);
    final hubsSpanMultipleServers = _hubsSpanMultipleServers();
    final browseHubs = _tvBrowseHubs;

    return TvSpotlightScaffold(
      hubs: browseHubs,
      spotlightListenable: _spotlight,
      resolveSpotlight: () => _spotlight.resolve(browseHubs),
      resolveClient: _getMediaClientForItem,
      hideSpoilers: hideSpoilers,
      foreground: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          if (_isLoading || (_areHubsLoading && browseHubs.isEmpty)) const Center(child: CircularProgressIndicator()),
          if (_errorMessage != null)
            ErrorStateWidget(
              message: _errorMessage!,
              icon: Symbols.error_outline_rounded,
              onRetry: _discover.load,
              actionAutofocus: true,
              actionUseBackgroundFocus: true,
            ),
          if (!_isLoading && _errorMessage == null && browseHubs.isEmpty && !_areHubsLoading)
            EmptyStateWidget(
              message: t.discover.noContentAvailable,
              subtitle: t.discover.addMediaToLibraries,
              icon: Symbols.movie_rounded,
            ),
          if (browseHubs.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _cachedTvBrowseRail(browseHubs, showServerName: showServerNameOnHubs || hubsSpanMultipleServers),
            ),
          // Under the redesign the screen draws no toolbar of its own: it puts
          // the same actions in the shell's top right corner, beside the
          // clock, through [OckerHeaderSlot]. See [_publishOckerHeaderChrome].
          if (!isOckerLayout(context)) TvToolbarOverlay(child: _buildOverlaidAppBar()),
          if (_switchingProfile) const ProfileSwitchingOverlay(),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    final useSideNav = PlatformDetector.shouldUseSideNavigation(context);
    final isTv = PlatformDetector.isTV();
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    // Mobile keeps its fixed hero, except that a landscape phone is shorter
    // than the hero itself; fill the viewport there and let the item compact.
    final heroHeight = isTv
        ? viewportHeight * 0.82
        : useSideNav
        ? viewportHeight * 0.75
        : isLandscape
        ? math.min(500 + statusBarHeight, viewportHeight)
        : 500 + statusBarHeight;
    return SliverToBoxAdapter(
      child: Focus(
        focusNode: _heroFocusNode,
        onKeyEvent: _handleHeroKeyEvent,
        child: SizedBox(
          height: heroHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              PageView.builder(
                controller: _heroController,
                itemCount: _onDeck.length,
                onPageChanged: (index) {
                  if (index >= 0 && index < _onDeck.length) {
                    _heroIndex.value = index;
                    _resetAutoScrollTimer();
                  }
                },
                itemBuilder: (context, index) {
                  return _buildHeroItem(_onDeck[index], heroHeight);
                },
              ),
              // Page indicators with animated progress and pause/play button.
              // Hidden on TV only (issue #600: pointer-only control unreachable
              // via d-pad) — never gated on transient input mode, which back-key
              // events, BT keyboards, and gamepads can flip on phones/desktop.
              if (!isTv)
                Positioned(
                  bottom: 16,
                  left: -26,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: .center,
                    children: [
                      // Pause/Play button
                      ClickableCursor(
                        child: GestureDetector(
                          onTap: () {
                            if (_isAutoScrollPaused) {
                              _resumeAutoScroll();
                            } else {
                              _pauseAutoScroll();
                            }
                          },
                          child: AppIcon(
                            _isAutoScrollPaused ? Symbols.play_arrow_rounded : Symbols.pause_rounded,
                            fill: 1,
                            color: Theme.of(context).colorScheme.onSurface,
                            size: 18,
                            semanticLabel: _isAutoScrollPaused
                                ? t.accessibility.autoScrollPlay
                                : t.accessibility.autoScrollPause,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<int>(
                        valueListenable: _heroIndex,
                        builder: (context, heroIndex, _) {
                          final range = _getVisibleDotRange();
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(range.end - range.start + 1, (i) {
                              final index = range.start + i;
                              final isActive = heroIndex == index;
                              final dotSize = _getDotSize(index, range.start, range.end);

                              return isActive
                                  ? ValueListenableBuilder<double>(
                                      valueListenable: _indicatorProgress,
                                      builder: (context, progress, child) {
                                        final maxWidth = dotSize * 3;
                                        final fillWidth = dotSize + ((maxWidth - dotSize) * progress);
                                        final onSurface = Theme.of(context).colorScheme.onSurface;
                                        return Container(
                                          margin: const EdgeInsets.symmetric(horizontal: 4),
                                          width: maxWidth,
                                          height: dotSize,
                                          decoration: BoxDecoration(
                                            color: onSurface.withValues(alpha: 0.4),
                                            borderRadius: BorderRadius.circular(dotSize / 2),
                                          ),
                                          child: Align(
                                            alignment: .centerLeft,
                                            child: Container(
                                              width: fillWidth,
                                              height: dotSize,
                                              decoration: BoxDecoration(
                                                color: onSurface,
                                                borderRadius: BorderRadius.circular(dotSize / 2),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                  : AnimatedContainer(
                                      duration: tokens(context).slow,
                                      curve: Curves.easeInOut,
                                      margin: const EdgeInsets.symmetric(horizontal: 4),
                                      width: dotSize,
                                      height: dotSize,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                                        borderRadius: BorderRadius.circular(dotSize / 2),
                                      ),
                                    );
                            }),
                          );
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroItem(MediaItem heroItem, double heroHeight) {
    final heroClient = _getMediaClientForItem(heroItem);
    final isEpisode = heroItem.isEpisode;
    final showName = heroItem.grandparentTitle ?? heroItem.displayTitle;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final heroAspectRatio = screenWidth / heroHeight;
    final heroArtPaths = heroItem.heroArtCandidates(containerAspectRatio: heroAspectRatio);
    final isLargeScreen = ScreenBreakpoints.isWideTabletOrLarger(screenWidth);
    final isTv = PlatformDetector.isTV();
    final alignLeft = isTv || isLargeScreen;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // A landscape phone hands the hero the whole ~400dp viewport; the usual
    // logo and bottom offset would push the content up into the top bar.
    final compact = !isTv && heroHeight < 450;
    final heroLogoWidth = isTv ? TvLayoutConstants.heroLogoWidth : 400.0;
    final heroLogoHeight = isTv
        ? TvLayoutConstants.heroLogoHeight
        : compact
        ? 80.0
        : 120.0;
    final heroTitleStyle = theme.textTheme.displaySmall?.copyWith(
      color: colorScheme.onSurface,
      // The serif has one weight; a faked bold on it is visible at a glance.
      fontWeight: isOcker(context) ? null : FontWeight.bold,
      fontSize: isTv ? 52 : null,
      shadows: [Shadow(color: colorScheme.surface.withValues(alpha: 0.8), blurRadius: 8)],
    );

    final contentTypeLabel = heroItem.isMovie ? t.discover.movie : t.discover.tvShow;

    final hideSpoilers = SettingsService.instance.read(SettingsService.hideSpoilers);
    final shouldHideSpoiler = hideSpoilers && heroItem.shouldHideSpoiler;

    final heroLabel = isEpisode ? "${heroItem.grandparentTitle}, ${heroItem.title}" : heroItem.title;

    return Semantics(
      label: heroLabel,
      button: true,
      hint: t.accessibility.tapToPlay,
      child: ClickableCursor(
        child: GestureDetector(
          onTap: () {
            appLogger.d('Activating hero item: ${heroItem.title}');
            navigateToMediaItem(context, heroItem, playDirectly: true);
          },
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              // Background Image with fade/zoom animation and parallax
              if (heroArtPaths.isNotEmpty)
                ClipRect(
                  child: AnimatedBuilder(
                    animation: _scrollController,
                    builder: (context, child) {
                      final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                      return Transform.translate(offset: Offset(0, scrollOffset * 0.3), child: child);
                    },
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOut,
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: 1.0 + (0.1 * (1 - value)),
                          child: Opacity(opacity: value, child: child),
                        );
                      },
                      child: Builder(
                        builder: (context) {
                          // heroClient resolves to the actual server's client
                          // (Plex or Jellyfin) so each backend's transcoder
                          // builds sized URLs.
                          return blurArtwork(
                            CyclingMediaBackdrop(
                              mediaKey: heroItem.globalKey,
                              imagePaths: heroItem.heroRotationPaths(containerAspectRatio: heroAspectRatio),
                              fallbackImagePaths: heroArtPaths,
                              client: heroClient,
                              active: _isTabVisible,
                              width: screenWidth,
                              height: heroHeight,
                              fallbackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                )
              else
                ColoredBox(color: colorScheme.surfaceContainerHighest),

              // Gradient Overlay - blends into scaffold background
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: -4, // Extend past stack bounds to ensure coverage
                child: IgnorePointer(
                  child: Builder(
                    builder: (context) {
                      final bgColor = Theme.of(context).scaffoldBackgroundColor;
                      return Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            // Reach full bg before the bottom edge so the hero
                            // blends seamlessly into the content below and the
                            // page dots sit on a solid band.
                            colors: [Colors.transparent, bgColor.withValues(alpha: 0.9), bgColor, bgColor],
                            stops: isTv ? const [0.25, 0.78, 0.94, 1.0] : const [0.5, 0.85, 0.94, 1.0],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Content with responsive alignment
              Positioned(
                bottom: isTv
                    ? 88
                    : compact
                    ? 24
                    : isLargeScreen
                    ? 80
                    : 50,
                left: 0,
                right: isTv
                    ? screenWidth * 0.36
                    : isLargeScreen
                    ? 200
                    : 0,
                // Horizontal-only SafeArea: the PageView artwork behind stays
                // full-bleed; the foreground text/buttons clear the landscape
                // notch. Vertical placement is handled by `bottom` above.
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Padding(
                    padding: .symmetric(
                      horizontal: isTv
                          ? TvLayoutConstants.horizontalInset
                          : isLargeScreen
                          ? 40
                          : 24,
                    ),
                    child: Align(
                      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isTv ? TvLayoutConstants.heroContentMaxWidth : double.infinity,
                        ),
                        child: Column(
                          crossAxisAlignment: alignLeft ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                          mainAxisSize: .min,
                          children: [
                            // Show logo, falling back to the name/title. The
                            // logo keeps its slot; the title gets a wider one.
                            LayoutBuilder(
                              builder: (context, constraints) => ClearLogoImage(
                                client: heroClient,
                                logoPath: heroItem.clearLogoPath,
                                item: heroItem,
                                width: math.min(heroLogoWidth, constraints.maxWidth),
                                height: heroLogoHeight,
                                fallbackWidth: ClearLogoImage.fallbackWidthFor(
                                  logoWidth: heroLogoWidth,
                                  available: constraints.maxWidth,
                                ),
                                alignment: alignLeft ? Alignment.bottomLeft : Alignment.bottomCenter,
                                // The hero scrim washes artwork toward the scaffold
                                // background; light themes recolor light-toned logos.
                                logoToneTarget: logoToneTargetFor(
                                  surface: theme.scaffoldBackgroundColor,
                                  foreground: colorScheme.onSurface,
                                ),
                                fallbackBuilder: (context) => FittingTitleText(
                                  showName,
                                  style: heroTitleStyle,
                                  textAlign: alignLeft ? TextAlign.left : TextAlign.center,
                                  alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
                                ),
                              ),
                            ),

                            // Metadata as dot-separated text with content type
                            if (heroItem.year != null || heroItem.contentRating != null || heroItem.rating != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                [
                                  contentTypeLabel,
                                  if (heroItem.rating != null) '★ ${formatRating(heroItem.rating!)}',
                                  if (heroItem.contentRating != null) formatContentRating(heroItem.contentRating!),
                                  if (heroItem.year != null) heroItem.year.toString(),
                                ].join(' • '),
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: isTv ? 18 : 14,
                                  fontWeight: .w600,
                                ),
                                textAlign: alignLeft ? TextAlign.left : TextAlign.center,
                              ),
                            ],

                            if (!alignLeft) ...[const SizedBox(height: 20), _buildSmartPlayButton(heroItem)],

                            if (heroItem.summary != null && !shouldHideSpoiler) ...[
                              const SizedBox(height: 12),
                              RichText(
                                maxLines: isTv ? 3 : 2,
                                overflow: .ellipsis,
                                textAlign: alignLeft ? TextAlign.left : TextAlign.center,
                                text: TextSpan(
                                  style: TextStyle(
                                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                                    fontSize: isTv ? 18 : 14,
                                    height: isTv ? 1.45 : 1.4,
                                  ),
                                  children: [
                                    if (isEpisode && heroItem.parentIndex != null && heroItem.index != null)
                                      TextSpan(
                                        text: 'S${heroItem.parentIndex}, E${heroItem.index}: ',
                                        style: TextStyle(fontWeight: .bold, color: colorScheme.onSurface),
                                      ),
                                    TextSpan(
                                      text: heroItem.summary?.isNotEmpty == true
                                          ? heroItem.summary!
                                          : t.messages.noDescriptionAvailable,
                                    ),
                                  ],
                                ),
                              ),
                            ] else if (shouldHideSpoiler &&
                                isEpisode &&
                                heroItem.parentIndex != null &&
                                heroItem.index != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                'S${heroItem.parentIndex}, E${heroItem.index}: ${heroItem.title}',
                                maxLines: 2,
                                overflow: .ellipsis,
                                textAlign: alignLeft ? TextAlign.left : TextAlign.center,
                                style: TextStyle(
                                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                                  fontSize: isTv ? 18 : 14,
                                  height: isTv ? 1.45 : 1.4,
                                ),
                              ),
                            ],

                            if (alignLeft) ...[SizedBox(height: isTv ? 28 : 20), _buildSmartPlayButton(heroItem)],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmartPlayButton(MediaItem rawHeroItem) {
    return Builder(
      builder: (context) {
        // The on-deck snapshot refetches shortly after a watch event; the store
        // patch bridges the gap so "minutes left" never lags.
        final heroItem = context.withFreshWatchState(rawHeroItem);
        final hasProgress = heroItem.hasActiveProgress;
        final isTv = PlatformDetector.isTV();

        final minutesLeft = hasProgress ? ((heroItem.durationMs! - heroItem.viewOffsetMs!) / 60_000).round() : 0;

        final progress = hasProgress ? heroItem.viewOffsetMs! / heroItem.durationMs! : 0.0;

        return ListenableBuilder(
          listenable: _heroFocusNode,
          builder: (context, _) {
            final showFocus = isTv && _heroFocusNode.hasFocus && InputModeTracker.isKeyboardMode(context);
            final colorScheme = Theme.of(context).colorScheme;
            // Under the Plebz palette it wears the logo's gradient instead.
            final plebzPlay = ockerPlebzPlay(context);
            final backgroundColor = showFocus ? colorScheme.primary : Colors.white;
            final foregroundColor = plebzPlay ? Colors.white : (showFocus ? colorScheme.onPrimary : Colors.black);
            final button = InkWell(
              onTap: () {
                appLogger.d('Playing: ${heroItem.title}');
                navigateToVideoPlayer(context, metadata: heroItem);
              },
              borderRadius: BorderRadius.all(Radius.circular(isTv ? 32 : 24)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                padding: .symmetric(horizontal: isTv ? 34 : 24, vertical: isTv ? 16 : 12),
                decoration: plebzPlay
                    ? null
                    : BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.all(Radius.circular(isTv ? 32 : 24)),
                        boxShadow: showFocus
                            ? flatShadows(context, [
                                BoxShadow(
                                  color: colorScheme.primary.withValues(alpha: 0.35),
                                  blurRadius: 28,
                                  spreadRadius: 4,
                                ),
                              ])
                            : null,
                      ),
                child: Row(
                  mainAxisSize: .min,
                  children: [
                    AppIcon(Symbols.play_arrow_rounded, fill: 1, size: isTv ? 28 : 20, color: foregroundColor),
                    SizedBox(width: isTv ? 12 : 8),
                    if (hasProgress) ...[
                      // Progress bar
                      Container(
                        width: isTv ? 56 : 40,
                        height: isTv ? 8 : 6,
                        decoration: BoxDecoration(
                          color: foregroundColor.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.all(Radius.circular(isTv ? 4 : 3)),
                        ),
                        child: FractionallySizedBox(
                          alignment: .centerLeft,
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              color: foregroundColor,
                              borderRadius: BorderRadius.all(Radius.circular(isTv ? 3 : 2)),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isTv ? 12 : 8),
                      Text(
                        t.discover.minutesLeft(minutes: minutesLeft),
                        style: TextStyle(
                          color: foregroundColor,
                          fontSize: isTv ? 18 : 14,
                          fontWeight: isTv ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ] else
                      Text(
                        t.common.play,
                        style: TextStyle(
                          color: foregroundColor,
                          fontSize: isTv ? 18 : 14,
                          fontWeight: isTv ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            );
            return plebzPlay ? OckerPlebzPlayGround(focused: showFocus, child: button) : button;
          },
        );
      },
    );
  }
}
