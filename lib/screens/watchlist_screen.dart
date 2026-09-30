import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../mixins/refreshable.dart';
import '../mixins/tab_visibility_aware.dart';
import '../models/catalog/catalog_item.dart';
import '../navigation/main_screen_scope.dart';
import '../providers/catalog_sources_provider.dart';
import '../providers/libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../media/ids.dart';
import '../media/media_library.dart';
import '../media/watchlist_filter.dart';
import '../services/catalog/catalog_source.dart';
import '../services/server_favorites_service.dart';
import '../services/settings_service.dart';
import '../focus/focusable_action_bar.dart';
import '../utils/app_logger.dart';
import '../utils/dialogs.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/app_menu.dart';
import '../widgets/catalog_source_logo.dart';
import '../widgets/focusable_tab_chip.dart';
import 'hub_detail_screen.dart';
import 'libraries/state_messages.dart';
import '../redesign/ocker_skin.dart';
import '../redesign/ocker_submenu.dart';

/// The Watchlist tab: the full watchlist of one provider, as a navigation
/// destination of its own.
///
/// The provider is chosen here and persisted, deliberately **not** taken from
/// [CatalogSourcesProvider.activeSource]: that one follows the Explore tab's
/// switcher, so binding to it made flipping Explore from Plex to Simkl quietly
/// swap the watchlist too. Sources with a watchlist appear as chips beside the
/// title whenever there is more than one to pick from.
///
/// The grid is [HubDetailScreen] in embedded mode, so this tab and the Explore
/// row's View All screen stay one implementation — sorting, pagination and
/// D-pad behaviour included.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => WatchlistScreenState();
}

/// One tab of the Watchlist screen: a catalog provider's watchlist, or the
/// media servers' own favorites.
class _WatchlistTab {
  const _WatchlistTab({required this.id, required this.label, this.source});

  /// Stored in [SettingsService.watchlistSource]; [WatchlistScreenState.favoritesTabId]
  /// for the favorites tab, otherwise the provider's enum name.
  final String id;
  final String label;

  /// Null for the favorites tab, which is served by the media servers.
  final CatalogSource? source;
}

class WatchlistScreenState extends State<WatchlistScreen>
    with Refreshable, FullRefreshable, TabVisibilityAware, FocusableTab, OckerSubmenuHost {
  /// Under the redesign the lists are rows under "Merkliste" in the side
  /// rail: the choice of which list belongs with the navigation, the filters
  /// stay over the posters they narrow.
  @override
  OckerRailMenu? get ockerRailMenu {
    if (!isOckerLayout(context)) return null;
    final tabs = _tabs(context, listen: false);
    if (tabs.length < 2) return null;
    final active = _activeTab(tabs);
    return OckerRailMenu.fromEntries<String>([
      for (final tab in tabs)
        AppMenuItem<String>(
          value: tab.id,
          leading: tab.source == null ? null : CatalogSourceLogo(tab.source!.id),
          icon: tab.source == null ? Symbols.favorite_rounded : null,
          label: tab.label,
          selected: tab.id == active?.id,
        ),
    ], _selectFromRail);
  }

  /// A list chosen in the rail: show it, and go into it once it is there.
  void _selectFromRail(String id) {
    _select(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _gridKey.currentState?.focusFromHostTab();
    });
  }

  /// Items per request, and the page ceiling that bounds a runaway watchlist.
  static const int _pageSize = 100;
  static const int _maxPages = 5;

  /// Pref value marking the server-favorites tab. Not a [CatalogSourceId]
  /// name, so it can never collide with a provider.
  static const String favoritesTabId = 'server_favorites';

  /// Recreated to remount the grid — a fresh key is what makes
  /// [HubDetailScreen] take a new snapshot.
  GlobalKey<HubDetailScreenState> _gridKey = GlobalKey<HubDetailScreenState>();

  final List<FocusNode> _sourceChipNodes = [];
  String? _selectedId;

  /// What the tab currently shows, and the closure the grid narrows with.
  ///
  /// The closure is held rather than built per frame: the grid re-filters when
  /// it is handed a *different* one, so a fresh closure on every rebuild would
  /// have it walk the whole list again for nothing.
  WatchlistFilter _filter = WatchlistFilter.none;
  bool Function(MediaItem item)? _itemFilter;

  @override
  void initState() {
    super.initState();
    final stored = SettingsService.instance.read(SettingsService.watchlistSource);
    _selectedId = stored.isEmpty ? null : stored;
    final settings = SettingsService.instance;
    _filter = WatchlistFilter(
      type: settings.read(SettingsService.watchlistTypeFilter),
      status: settings.read(SettingsService.watchlistStatusFilter),
    );
    _itemFilter = _filter.isEmpty ? null : _filter.matches;
  }

  @override
  void dispose() {
    for (final node in _sourceChipNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Libraries whose server can serve favorites, and the lookup that resolves
  /// their clients. Nullable reads: hosts without these providers (widget
  /// tests) simply never see the Favorites tab.
  List<MediaLibrary> _libraries(BuildContext context, {bool listen = true}) =>
      Provider.of<LibrariesProvider?>(context, listen: listen)?.libraries ?? const [];

  ClientLookup _clientLookup(BuildContext context) {
    final multiServer = context.read<MultiServerProvider?>();
    return (serverId) => multiServer?.serverManager.getClient(ServerId(serverId));
  }

  /// The tabs on offer: one per catalog provider with a watchlist, plus the
  /// media servers' favorites when any connected server has them.
  List<_WatchlistTab> _tabs(BuildContext context, {bool listen = true}) {
    final sources =
        Provider.of<CatalogSourcesProvider?>(context, listen: listen)?.watchlistCapableSources ??
        const <CatalogSource>[];
    final tabs = [
      for (final source in sources) _WatchlistTab(id: source.id.name, label: source.displayName, source: source),
    ];
    final libraries = _libraries(context, listen: listen);
    final clientFor = _clientLookup(context);
    if (libraries.isNotEmpty &&
        ServerFavoritesService.hasFavoritesCapableLibrary(libraries: libraries, clientFor: clientFor)) {
      tabs.add(_WatchlistTab(id: favoritesTabId, label: _favoritesTabLabel(libraries, clientFor)));
    }
    return tabs;
  }

  /// The favorites tab is named after the server it reads, not "Favorites":
  /// beside a "Plex" chip the generic word says nothing about which of the two
  /// it belongs to. Falls back to the generic word when Jellyfin and Emby
  /// servers are connected at once and no single product owns the tab.
  String _favoritesTabLabel(List<MediaLibrary> libraries, ClientLookup clientFor) {
    final names = <String>{
      for (final library in libraries)
        if (library.serverId case final serverId?)
          if (clientFor(serverId) case final client? when client.capabilities.userFavorites)
            ?client.backend.dialect?.productName,
    };
    return names.length == 1 ? names.single : t.libraries.filterCategories.favorites;
  }

  /// The chosen tab, or the first available one when the stored choice is gone
  /// (provider disconnected, server offline) or was never made.
  _WatchlistTab? _activeTab(List<_WatchlistTab> tabs) {
    if (tabs.isEmpty) return null;
    return tabs.firstWhereOrNull((tab) => tab.id == _selectedId) ?? tabs.first;
  }

  void _select(String id) {
    if (_selectedId == id) return;
    setState(() {
      _selectedId = id;
      _gridKey = GlobalKey<HubDetailScreenState>();
    });
    unawaited(SettingsService.instance.write(SettingsService.watchlistSource, id));
  }

  /// Narrow the list to [filter]. The grid keeps the items it has — the
  /// watchlist is a whole provider's list, and refetching it to hide half of
  /// it would cost several requests for an answer already on screen.
  void _applyFilter(WatchlistFilter filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      _itemFilter = filter.isEmpty ? null : filter.matches;
    });
    final settings = SettingsService.instance;
    unawaited(settings.write(SettingsService.watchlistTypeFilter, filter.type));
    unawaited(settings.write(SettingsService.watchlistStatusFilter, filter.status));
  }

  Future<void> _pickTypeFilter() async {
    final picked = await showOptionPickerDialog<WatchlistTypeFilter>(
      context,
      title: t.watchlist.typeFilter,
      options: [
        (icon: Symbols.category_rounded, label: t.watchlist.allTypes, value: WatchlistTypeFilter.all),
        (icon: Symbols.movie_rounded, label: t.watchlist.moviesOnly, value: WatchlistTypeFilter.movies),
        (icon: Symbols.tv_rounded, label: t.watchlist.showsOnly, value: WatchlistTypeFilter.shows),
      ],
    );
    if (picked != null && mounted) _applyFilter(_filter.withType(picked));
  }

  Future<void> _pickStatusFilter() async {
    final picked = await showOptionPickerDialog<WatchlistStatusFilter>(
      context,
      title: t.watchlist.statusFilter,
      options: [
        (icon: Symbols.filter_alt_rounded, label: t.watchlist.anyStatus, value: WatchlistStatusFilter.any),
        (
          icon: Symbols.visibility_off_rounded,
          label: t.watchlist.unwatchedOnly,
          value: WatchlistStatusFilter.unwatched,
        ),
        (icon: Symbols.visibility_rounded, label: t.watchlist.watchedOnly, value: WatchlistStatusFilter.watched),
      ],
    );
    if (picked != null && mounted) _applyFilter(_filter.withStatus(picked));
  }

  /// The two narrowing actions, left of the grid's own sort. Each wears the
  /// choice it holds, so a list that is missing half its titles says why
  /// without being opened.
  List<FocusableAction> _filterActions() => [
    FocusableAction(
      icon: switch (_filter.type) {
        WatchlistTypeFilter.all => Symbols.category_rounded,
        WatchlistTypeFilter.movies => Symbols.movie_rounded,
        WatchlistTypeFilter.shows => Symbols.tv_rounded,
      },
      iconFill: _filter.type == WatchlistTypeFilter.all ? 0 : 1,
      tooltip: t.watchlist.typeFilter,
      onPressed: _pickTypeFilter,
    ),
    FocusableAction(
      icon: switch (_filter.status) {
        WatchlistStatusFilter.any => Symbols.filter_alt_rounded,
        WatchlistStatusFilter.unwatched => Symbols.visibility_off_rounded,
        WatchlistStatusFilter.watched => Symbols.visibility_rounded,
      },
      iconFill: _filter.status == WatchlistStatusFilter.any ? 0 : 1,
      tooltip: t.watchlist.statusFilter,
      onPressed: _pickStatusFilter,
    ),
  ];

  void _reload() => setState(() => _gridKey = GlobalKey<HubDetailScreenState>());

  @override
  void onTabShown() {
    // Pick up watchlist changes made elsewhere in the app while this tab sat
    // in the IndexedStack.
    _reload();
  }

  @override
  void onTabHidden() {}

  @override
  void refresh() => _reload();

  @override
  void fullRefresh() => _reload();

  /// The grid loads itself on mount; a prime on top would only fetch twice.
  @override
  void primeRefresh() {}

  /// Focus lands in the grid only once this tab is the visible one — the
  /// embedded [HubDetailScreen] deliberately does not grab it on mount.
  @override
  void focusActiveTabIfReady() {
    // A frame of its own: the host calls this from a frame's end, and with
    // nothing else asking for one the cursor waited for the next key press —
    // DOWN out of the navigation had to be pressed twice.
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gridKey.currentState?.focusFromHostTab();
    });
  }

  /// The items behind [tab]: a provider's watchlist, or the servers' favorites.
  Future<List<MediaItem>> _loadTab(BuildContext context, _WatchlistTab tab) {
    final source = tab.source;
    if (source != null) return _loadWatchlist(source);
    return const ServerFavoritesService().fetchFavorites(
      libraries: _libraries(context),
      clientFor: _clientLookup(context),
    );
  }

  /// Every page of the chosen provider's watchlist, concatenated.
  Future<List<MediaItem>> _loadWatchlist(CatalogSource source) async {
    final items = <MediaItem>[];
    for (var page = 1; page <= _maxPages; page++) {
      final result = await source.fetchRow(CatalogRowId.watchlist, page: page, limit: _pageSize);
      items.addAll([for (final item in result.items) item.toMediaItem()]);
      if (!result.hasMore) return items;
    }
    appLogger.w('Watchlist: ${source.id.name} truncated at ${items.length} items ($_maxPages pages)');
    return items;
  }

  FocusNode _chipNode(int index) {
    while (_sourceChipNodes.length <= index) {
      _sourceChipNodes.add(FocusNode(debugLabel: 'watchlist_source_${_sourceChipNodes.length}'));
    }
    return _sourceChipNodes[index];
  }

  /// Title plus, when there is more than one list to choose from, a chip per
  /// tab.
  Widget _buildTitle(List<_WatchlistTab> tabs, _WatchlistTab active) {
    final title = Text(t.explore.rows.watchlist);
    // The redesign chooses the list in the side rail instead; see
    // [ockerRailMenu]. Only the name stays here.
    if (tabs.length < 2 || isOckerLayout(context)) return title;

    return TabChipStrip(
      children: [
        // Under "Ocker" the section heading above already says "Merkliste",
        // and the strip sits directly over the posters — so it is only the
        // switcher, with nothing repeated in front of it.
        if (!isOcker(context)) Padding(padding: const EdgeInsets.only(right: 12), child: title),
        for (var index = 0; index < tabs.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          FocusableTabChip(
            label: tabs[index].label,
            isSelected: tabs[index].id == active.id,
            focusNode: _chipNode(index),
            onSelect: () => _select(tabs[index].id),
            onNavigateLeft: index > 0
                ? () => _chipNode(index - 1).requestFocus()
                : () => MainScreenFocusScope.focusSidebarOf(context),
            // Past the last chip lies the app bar's own action (sort), so the
            // strip hands focus on rather than swallowing RIGHT.
            onNavigateRight: index < tabs.length - 1
                ? () => _chipNode(index + 1).requestFocus()
                : () => _gridKey.currentState?.focusAppBarFromHost(),
            onNavigateDown: () => _gridKey.currentState?.focusFromHostTab(),
            // The switcher is the last rung before the navigation.
            onNavigateUp: () => MainScreenFocusScope.focusSidebarOf(context),
            onBack: () => MainScreenFocusScope.focusSidebarOf(context),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs(context);
    final active = _activeTab(tabs);

    if (active == null) {
      return Scaffold(
        body: CustomScrollView(
          slivers: [
            CustomAppBar(title: Text(t.explore.rows.watchlist), pinned: true, automaticallyImplyLeading: false),
            SliverFillRemaining(
              child: EmptyStateWidget(message: t.explore.emptyTitle, icon: Symbols.bookmark_rounded),
            ),
          ],
        ),
      );
    }

    return HubDetailScreen(
      key: _gridKey,
      // The watchlist keeps the redesign's shape in both "Ocker" variants: it
      // is one list with nothing above it, and the panel describing whatever
      // holds focus is worth more here than anywhere else this screen serves.
      ockerPageInAnyLayout: true,
      hub: MediaHub(
        id: 'watchlist:${active.id}',
        identifier: 'watchlist.${active.id}',
        title: active.source == null ? active.label : t.explore.rows.watchlist,
        type: 'mixed',
        items: const [],
        size: 0,
        // The grid owns the fetch: `more` is what makes it call loadItems, and
        // starting from an empty list keeps the whole watchlist on one code
        // path instead of pasting a row snapshot in front of it.
        more: true,
      ),
      loadItems: () => _loadTab(context, active),
      isEmbedded: true,
      itemFilter: _itemFilter,
      hostAppBarActions: _filterActions(),
      titleOverride: _buildTitle(tabs, active),
      // LEFT out of the app bar actions lands on the last source chip, which
      // is the only way the D-pad can reach the switcher: UP from the grid
      // goes to the actions, not into the title.
      // Under the redesign the lists are in the rail, and left of the first
      // filter is the rail itself — [HubDetailScreen]'s own default.
      onAppBarNavigateLeft: isOckerLayout(context) || tabs.length < 2
          ? null
          : () => _chipNode(tabs.length - 1).requestFocus(),
    );
  }
}
