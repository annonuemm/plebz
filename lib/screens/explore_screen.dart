import 'dart:async';

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../focus/focusable_action_bar.dart';
import '../focus/hub_vertical_navigation.dart';
import '../focus/locked_hub_controller.dart';
import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../mixins/debounced_media_search.dart';
import '../mixins/refreshable.dart';
import '../mixins/tab_visibility_aware.dart';
import '../models/catalog/catalog_item.dart';
import '../navigation/main_screen_scope.dart';
import '../providers/catalog_sources_provider.dart';
import '../providers/explore_provider.dart';
import '../services/catalog/catalog_source.dart';
import '../services/catalog/plex_catalog_source.dart';
import '../services/catalog/seerr_catalog_source.dart';
import '../services/catalog/seerr_shelves.dart';
import '../utils/app_logger.dart';
import '../services/settings_service.dart';
import '../utils/platform_detector.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/provider_extensions.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_menu.dart';
import '../widgets/catalog_source_logo.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/hub_section.dart';
import '../widgets/focusable_media_card.dart';
import '../widgets/focusable_popup_menu_button.dart';
import '../widgets/loading_indicator_box.dart';
import '../widgets/search_input_field.dart';
import '../widgets/settings_builder.dart';
import '../widgets/toolbar_scrim.dart';
import '../widgets/tv_browse_rail.dart';
import '../widgets/tv_spotlight_scaffold.dart';
import 'plex_section_screen.dart';
import 'catalog_search_screen.dart';
import 'trailer_stage/trailer_stage_setup_screen.dart';
import 'seerr_shelf_screen.dart';
import 'libraries/state_messages.dart';
import '../redesign/ocker_skin.dart';
import '../theme/mono_tokens.dart';
import '../redesign/ocker_submenu.dart';
import 'package:collection/collection.dart';

/// The Explore tab: watchlist + discover rows from the active external
/// catalog source (Trakt). Only mounted when a source is connected (the tab
/// is hidden otherwise, see [NavigationTab.getVisibleTabs]).
///
/// Touch/pointer builds carry an inline search field under the app bar whose
/// results replace the rows while the query is non-empty. TV keeps the
/// toolbar's search action instead: a text field cannot share the spotlight
/// scaffold with the bottom-pinned browse rail and the on-screen keyboard,
/// so that path pushes [CatalogSearchScreen].
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => ExploreScreenState();
}

/// The first title from [page] that has artwork wide enough to stand behind
/// the shelf.
///
/// Reads [MediaItem.resolvedBackdropPaths], **not** the raw `backdropPaths`
/// field. A catalog item converted with `toCatalogItem` carries its wide image
/// in `artPath` and leaves `backdropPaths` null, so a filter on the raw field
/// discards every candidate and the brand tile keeps showing its logo — which
/// is precisely how this feature shipped inert.
/// The first title from [page] with artwork wide enough to stand behind the
/// shelf, skipping anything [taken] by another brand.
///
/// Reads [MediaItem.resolvedBackdropPaths], **not** the raw `backdropPaths`
/// field: a converted catalog item keeps its wide image in `artPath`, so a
/// filter on the raw field discards every candidate.
///
/// [taken] is what stops two providers showing the same film. Popularity
/// order puts co-produced titles at the top of several brands at once, and a
/// shelf where three tiles share one backdrop says nothing about any of them.
MediaItem? brandSpotlightTitleFrom(CatalogPage page, {Set<String> taken = const {}}) => page.items
    .map((item) => item.toMediaItem())
    .where((item) => item.resolvedBackdropPaths.isNotEmpty && !taken.contains(item.globalKey))
    .firstOrNull;

class ExploreScreenState extends State<ExploreScreen>
    with
        ManualRefreshable,
        FullRefreshable,
        TabVisibilityAware,
        FocusableTab,
        DebouncedMediaSearch<ExploreScreen, MediaItem>,
        OckerSubmenuHost {
  /// What stands behind "Erkunden", as rows under it in the side rail: which
  /// provider, search, refresh — the row that used to sit on the backdrop
  /// this design no longer has.
  @override
  OckerRailMenu? get ockerRailMenu {
    final entries = _ockerMenuEntries();
    return entries == null ? null : OckerRailMenu.fromEntries(entries, _onOckerMenuChosen);
  }

  List<AppMenuEntry<String>>? _ockerMenuEntries() {
    final sources = context.read<CatalogSourcesProvider>();
    final active = sources.activeSource;
    if (active == null) return null;
    final connected = sources.connectedSources;
    return [
      if (connected.length > 1) ...[
        for (final source in connected)
          AppMenuItem<String>(
            value: 'source:${source.id.name}',
            leading: CatalogSourceLogo(source.id),
            label: source.displayName,
            selected: source.id == active.id,
          ),
        const AppMenuDivider<String>(),
      ],
      AppMenuItem<String>(value: 'trailerStage', icon: Symbols.theaters_rounded, label: t.trailerStage.title),
      AppMenuItem<String>(value: 'search', icon: Symbols.search_rounded, label: t.common.search),
      AppMenuItem<String>(value: 'refresh', icon: Symbols.refresh_rounded, label: t.common.refresh),
    ];
  }

  void _onOckerMenuChosen(String chosen) {
    final sources = context.read<CatalogSourcesProvider>();
    final active = sources.activeSource;
    if (active == null) return;
    if (chosen == 'search') {
      unawaited(
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CatalogSearchScreen(source: active))),
      );
      return;
    }
    if (chosen == 'refresh') {
      unawaited(_explore.load());
      return;
    }
    if (chosen == 'trailerStage') {
      _openTrailerStage();
      return;
    }
    final id = sources.connectedSources.firstWhereOrNull((s) => 'source:${s.id.name}' == chosen)?.id;
    if (id != null) unawaited(sources.setActiveSource(id));
  }

  late ExploreProvider _explore;
  late CatalogSourcesProvider _sources;
  CatalogSourceId? _activeSourceId;

  /// Per-row focus keys, keyed by hub id so focus memory survives reloads.
  final Map<String, GlobalKey<HubSectionState>> _hubKeysById = {};
  List<GlobalKey<HubSectionState>> _orderedHubKeys = const [];
  final _actionBarKey = GlobalKey<FocusableActionBarState>();
  final _sourceMenuKey = GlobalKey<AppMenuButtonState<CatalogSourceId>>();

  final _tvBrowseRailKey = GlobalKey<TvBrowseRailState>();
  final _hubFocusMemory = HubFocusMemory();
  final TvSpotlightController _spotlight = TvSpotlightController();

  @override
  String get searchDebugLabel => 'ExploreSearch';

  /// Results take over the page the moment the field holds text: the mixin's
  /// [hasSearched] only flips once a query actually runs, so keying the swap
  /// off that would flash the rows back for the length of every debounce.
  bool get searchIsActive => searchController.text.trim().isNotEmpty;

  @override
  Future<List<MediaItem>> performSearchQuery(String query) async {
    final source = _explore.activeSource;
    if (source == null) return const [];
    final items = await source.search(query);
    return [for (final item in items) item.toMediaItem()];
  }

  @override
  void initState() {
    super.initState();
    _explore = context.read<ExploreProvider>();
    _explore.ensureFresh();
    _sources = context.read<CatalogSourcesProvider>();
    _activeSourceId = _sources.activeSource?.id;
    _sources.addListener(_onActiveSourceChanged);
  }

  /// A live query belongs to the source it was typed against, so a source
  /// switch re-runs it instead of leaving the previous source's results
  /// sitting under the new source's name.
  void _onActiveSourceChanged() {
    final id = _sources.activeSource?.id;
    if (id == _activeSourceId) return;
    _activeSourceId = id;
    if (!mounted) return;
    final query = searchController.text.trim();
    if (query.isEmpty) return;
    unawaited(runSearch(query));
  }

  @override
  void manualRefresh() => unawaited(_handleRefresh());

  /// Pull-to-refresh and the toolbar refresh action: re-run the query that is
  /// actually on screen, not the hidden rows behind it.
  Future<void> _handleRefresh() {
    final query = searchController.text.trim();
    if (query.isNotEmpty) return runSearch(query);
    return _explore.load();
  }

  @override
  void fullRefresh() {
    // Clearing routes through the text listener, which resets the search state.
    searchController.clear();
    unawaited(_explore.load());
  }

  @override
  void onTabShown() {
    _explore.ensureFresh();
  }

  @override
  void onTabHidden() {}

  @override
  void dispose() {
    _sources.removeListener(_onActiveSourceChanged);
    _brandSpotlightTimer?.cancel();
    _spotlight.dispose();
    super.dispose();
  }

  @override
  void focusActiveTabIfReady() {
    if (PlatformDetector.isTV()) {
      if (_explore.rowHubs.isNotEmpty) {
        _tvBrowseRailKey.currentState?.requestFocus();
      } else if (isOckerLayout(context)) {
        // Nothing on the screen to claim: the header is where the actions are.
        _navigateToSidebar();
      } else {
        _actionBarKey.currentState?.requestFocusOnFirst();
      }
      return;
    }
    if (searchIsActive) {
      // Never re-open the soft keyboard on a tab switch when results are
      // already there to land on.
      if (searchResults.isNotEmpty) {
        firstResultFocusNode.requestFocus();
      } else {
        searchFocusNode.requestFocus();
      }
      return;
    }
    _orderedHubKeys.firstOrNull?.currentState?.requestFocusFromMemory();
  }

  /// What the big backdrop shows for the focused tile.
  ///
  /// A studio or streaming-service tile is a logo on a flat card — as a
  /// full-screen backdrop that is a wordmark on grey. So for those, one of the
  /// brand's own titles is put in the spotlight instead: fetched when the
  /// cursor comes to rest, remembered for the session, and only applied while
  /// the same tile is still focused.
  void _setSpotlightItem(MediaItem item) {
    final brand = ExploreProvider.brandKeyOf(item);
    if (brand == null) {
      _brandSpotlightTimer?.cancel();
      _setBrandFocused(false);
      _spotlight.select(item);
      return;
    }

    _setBrandFocused(true);
    if (_brandSpotlights[brand] case final title?) {
      _spotlight.select(title);
      return;
    }

    // Nothing stands in while the title is fetched. The logo used to, and a
    // wordmark blown up to fill the screen and then swapped is worse than a
    // moment of plain ground.
    _focusedBrand = brand;
    _brandSpotlightTimer?.cancel();
    _brandSpotlightTimer = Timer(const Duration(milliseconds: 400), () => unawaited(_loadBrandSpotlight(brand)));
  }

  /// Whether the cursor rests on a studio or provider tile.
  ///
  /// Two things hang on it: the spotlight writes no title or summary there —
  /// the picture stands for the brand, not for the film it happens to be —
  /// and until one is fetched there is nothing to show at all.
  bool _brandFocused = false;

  void _setBrandFocused(bool value) {
    if (_brandFocused == value || !mounted) return;
    setState(() => _brandFocused = value);
  }

  /// The brand tile's own spotlight, or null while it is still being fetched.
  MediaItem? _resolveExploreSpotlight(List<MediaHub> hubs) {
    if (_brandFocused) {
      final brand = _focusedBrand;
      return brand == null ? null : _brandSpotlights[brand];
    }
    return _spotlight.resolve(hubs);
  }

  Future<void> _loadBrandSpotlight(String brand) async {
    final source = _explore.activeSource;
    if (source is! SeerrCatalogSource || _brandSpotlights.containsKey(brand)) return;

    final parts = brand.split(':');
    final id = int.tryParse(parts.last);
    if (id == null) return;

    try {
      final page = parts.first == 'studio'
          ? await source.discoverMoviesPage(studio: id, sortBy: 'popularity.desc')
          : await source.discoverTvPage(network: id, sortBy: 'popularity.desc');
      final title = brandSpotlightTitleFrom(page, taken: {for (final t in _brandSpotlights.values) t.globalKey});
      if (title == null || !mounted) return;
      _brandSpotlights[brand] = title;
      // Only if the cursor is still there: by now it may have moved on.
      if (_focusedBrand == brand) _spotlight.select(title);
    } catch (error, stackTrace) {
      appLogger.d('Explore: brand spotlight failed for $brand', error: error, stackTrace: stackTrace);
    }
  }

  /// One title per brand, kept for the session — the shelf is fixed, and so is
  /// what stands behind each of its tiles.
  final Map<String, MediaItem> _brandSpotlights = {};
  String? _focusedBrand;
  Timer? _brandSpotlightTimer;

  void _updateHubKeys(List<ExploreRowHub> rowHubs) {
    final liveIds = <String>{for (final rowHub in rowHubs) rowHub.hub.id};
    _hubKeysById.removeWhere((id, _) => !liveIds.contains(id));
    _orderedHubKeys = [
      for (final rowHub in rowHubs) _hubKeysById.putIfAbsent(rowHub.hub.id, GlobalKey<HubSectionState>.new),
    ];
  }

  bool _handleVerticalNavigation(int hubIndex, bool isUp) {
    final keys = _orderedHubKeys;
    return navigateVerticalHubRows(
      hubCount: keys.length,
      hubIndex: hubIndex,
      isUp: isUp,
      onTopBoundary: searchFocusNode.requestFocus,
      requestFocus: (targetIndex) {
        keys[targetIndex].currentState?.requestFocusFromMemory();
      },
    );
  }

  void _navigateToSidebar() {
    MainScreenFocusScope.focusSidebarOf(context);
  }

  static IconData _rowIcon(CatalogRowId? row) => switch (row) {
    null => Symbols.thumb_up_rounded,
    CatalogRowId.recentlyAdded => Symbols.new_releases_rounded,
    CatalogRowId.watchlist => Symbols.bookmark_rounded,
    CatalogRowId.recommendedMovies ||
    CatalogRowId.recommendedShows ||
    CatalogRowId.suggestedAnime => Symbols.thumb_up_rounded,
    CatalogRowId.trendingMovies ||
    CatalogRowId.trendingShows ||
    CatalogRowId.trendingAnime ||
    CatalogRowId.airingAnime ||
    CatalogRowId.trending => Symbols.trending_up_rounded,
    CatalogRowId.popularMovies || CatalogRowId.popularShows || CatalogRowId.popularAnime => Symbols.whatshot_rounded,
    CatalogRowId.upcomingMovies || CatalogRowId.upcomingShows => Symbols.event_upcoming_rounded,
  };

  List<AppMenuEntry<CatalogSourceId>> _sourceMenuEntries(CatalogSourcesProvider sources, CatalogSource active) => [
    for (final source in sources.connectedSources)
      AppMenuItem<CatalogSourceId>(
        value: source.id,
        leading: CatalogSourceLogo(source.id),
        label: source.displayName,
        selected: source.id == active.id,
      ),
  ];

  /// The service you are browsing, as this design writes a label.
  ///
  /// The same voice the shelf headings use — mono, upright, letterspaced,
  /// upper case — because that is what this is: not the title of the page but
  /// the name of what the page is showing. A chevron after it says the word
  /// can be pressed, the same chevron the header puts on a destination with
  /// something behind it.
  ///
  /// No service logo. The headings dropped their glyph for the same reason a
  /// row's name needs no picture beside it, and a brand mark here would be the
  /// one coloured thing in a line of text.
  Widget _buildOckerSourceTrigger(CatalogSource active, TextStyle? textStyle) {
    final tk = tokens(context);
    final base = textStyle ?? Theme.of(context).textTheme.titleLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: .min,
        children: [
          Text(
            active.displayName.toUpperCase(),
            style: base?.copyWith(
              fontFamily: tk.monoFontFamily,
              fontSize: (base.fontSize ?? 20) * 0.74,
              fontWeight: FontWeight.w400,
              letterSpacing: 1.9,
              color: base.color ?? tk.ink(1),
            ),
          ),
          const SizedBox(width: 7),
          AppIcon(Symbols.keyboard_arrow_down_rounded, size: 17, color: tk.ink(0.55)),
        ],
      ),
    );
  }

  Widget _buildSourceSwitcher(
    CatalogSourcesProvider sources,
    CatalogSource active, {
    TextStyle? textStyle,
    AppMenuAnchorAlignment anchorAlignment = AppMenuAnchorAlignment.start,
    bool parentOwnsFocus = false,
  }) {
    final trigger = isOcker(context)
        ? _buildOckerSourceTrigger(active, textStyle)
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: .min,
              children: [
                CatalogSourceLogo(active.id, size: 22),
                const SizedBox(width: 8),
                Text(active.displayName, style: textStyle ?? Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 4),
                const AppIcon(Symbols.arrow_drop_down_rounded, fill: 1, size: 24),
              ],
            ),
          );
    if (parentOwnsFocus) {
      return AppMenuButton<CatalogSourceId>(
        key: _sourceMenuKey,
        tooltip: t.explore.selectSource,
        anchorAlignment: anchorAlignment,
        onSelected: (id) => unawaited(sources.setActiveSource(id)),
        entriesBuilder: (context) => _sourceMenuEntries(sources, active),
        child: trigger,
      );
    }
    return FocusablePopupMenuButton<CatalogSourceId>(
      menuKey: _sourceMenuKey,
      tooltip: t.explore.selectSource,
      semanticLabel: t.explore.selectSource,
      semanticValue: active.displayName,
      anchorAlignment: anchorAlignment,
      onSelected: (id) => unawaited(sources.setActiveSource(id)),
      itemBuilder: (context) => _sourceMenuEntries(sources, active),
      child: trigger,
    );
  }

  /// App-bar title: the active source name, as a switcher dropdown when more
  /// than one source is connected (mirrors the libraries dropdown).
  Widget _buildTitle(CatalogSourcesProvider sources) {
    final active = sources.activeSource;
    if (active == null) return Text(t.explore.title);
    if (sources.connectedSources.length < 2) {
      return Text(active.displayName);
    }
    return _buildSourceSwitcher(sources, active);
  }

  @override
  Widget build(BuildContext context) {
    final explore = context.watch<ExploreProvider>();
    final sources = context.watch<CatalogSourcesProvider>();
    final rowHubs = explore.rowHubs;
    _updateHubKeys(rowHubs);

    // The TV toolbar must remain mounted for loading, error, and empty
    // sources so users can always switch away from a source with no rows.
    if (PlatformDetector.isTV()) {
      return SettingsBuilder(
        prefs: const [SettingsService.hideSpoilers, SettingsService.libraryDensity, SettingsService.episodePosterMode],
        builder: (context) => _buildTvContent(rowHubs, sources),
      );
    }

    // One header mode for every state. Flipping floating/pinned between the
    // loading/empty scroll view and the content scroll view swaps the
    // SliverPersistentHeader variant (a different element type), which
    // reparents the GlobalKey'd action bar into a header that builds its
    // children during performLayout — and if a tooltip overlay is showing at
    // that moment (hover on refresh), its OverlayPortal re-activation
    // mutates the render tree mid-layout and asserts. Floating behaves
    // identically to pinned over the non-scrolling state widgets, so nothing
    // is lost by unifying.
    Widget appBar() => DesktopSliverAppBar(
      title: _buildTitle(sources),
      pinned: false,
      floating: true,
      snap: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      scrolledUnderElevation: 0,
      actions: [
        FocusableActionBar(
          key: _actionBarKey,
          onNavigateDown: searchFocusNode.requestFocus,
          actions: [
            FocusableAction(icon: Symbols.refresh_rounded, tooltip: t.common.refresh, onPressed: manualRefresh),
          ],
        ),
      ],
    );

    // The field sits in every state, so the sliver list keeps one shape and
    // search stays reachable while the rows are loading, empty, or failed.
    Widget searchField() => SliverToBoxAdapter(
      child: SearchInputField(
        controller: searchController,
        focusNode: searchFocusNode,
        debugLabel: searchDebugLabel,
        hintText: t.explore.searchHint(source: sources.activeSource?.displayName ?? ''),
        onNavigateLeft: _navigateToSidebar,
        onNavigateDown: _searchFieldDownTarget(),
        onEditingComplete: handleSearchSubmit,
      ),
    );

    Widget scroll(List<Widget> body) => CustomScrollView(
      // Android clamping physics won't start a drag on non-filling
      // content, killing pull-to-refresh in the loading/empty/error
      // states without this.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [appBar(), searchField(), ...body],
    );

    Widget content;
    if (searchIsActive) {
      content = scroll([_buildSearchResults()]);
    } else if (rowHubs.isEmpty && explore.isLoading) {
      content = scroll(const [SliverFillRemaining(child: Center(child: CircularProgressIndicator()))]);
    } else if (rowHubs.isEmpty && explore.state == ExploreLoadState.error) {
      content = scroll([
        SliverFillRemaining(
          child: ErrorStateWidget(
            message: explore.errorMessage ?? t.explore.emptyTitle,
            icon: Symbols.error_outline_rounded,
            onRetry: () => unawaited(_explore.load()),
          ),
        ),
      ]);
    } else if (rowHubs.isEmpty) {
      content = scroll([
        SliverFillRemaining(
          child: EmptyStateWidget(
            message: t.explore.emptyMessage(source: explore.activeSource?.displayName ?? ''),
            icon: Symbols.explore_rounded,
          ),
        ),
      ]);
    } else {
      content = scroll([
        for (var i = 0; i < rowHubs.length; i++)
          SliverToBoxAdapter(
            child: HubSection(
              key: _orderedHubKeys[i],
              hub: rowHubs[i].hub,
              totalResults: rowHubs[i].totalResults,
              focusMemory: _hubFocusMemory,
              icon: _rowIcon(rowHubs[i].row),
              loadMoreItems: rowHubs[i].hub.more ? () => _explore.loadAllForHub(rowHubs[i]) : null,
              // The same handler the television rail gets. Without it a tile
              // fell through to the ordinary title navigation, which opened a
              // detail page for something that is not a title.
              onItemTap: (item) => unawaited(_openTappedItem(rowHubs[i].hub, item)),
              onVerticalNavigation: (isUp) => _handleVerticalNavigation(i, isUp),
              onNavigateUp: i == 0 ? searchFocusNode.requestFocus : null,
              onNavigateToSidebar: _navigateToSidebar,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ]);
    }

    return Scaffold(
      body: RefreshIndicator(onRefresh: _handleRefresh, child: content),
    );
  }

  /// DOWN out of the field: the first result when there is one to land on,
  /// otherwise the first shelf behind the (empty) query.
  VoidCallback? _searchFieldDownTarget() {
    if (searchIsActive) {
      return searchResults.isNotEmpty && !isSearching ? firstResultFocusNode.requestFocus : null;
    }
    final first = _orderedHubKeys.firstOrNull;
    if (first == null) return null;
    return () => first.currentState?.requestFocusFromMemory();
  }

  Widget _buildSearchResults() {
    if (isSearching) return LoadingIndicatorBox.sliver;
    if (lastSearchFailed) {
      return SliverFillRemaining(
        child: StateMessageWidget(message: t.explore.searchFailed, icon: Symbols.error_rounded, iconSize: 80),
      );
    }
    // The debounce window right after the field goes from empty to typed: no
    // query has run yet, so there is nothing truthful to show.
    if (!hasSearched) return const SliverToBoxAdapter(child: SizedBox.shrink());
    if (searchResults.isEmpty) {
      return SliverFillRemaining(
        child: StateMessageWidget(
          message: t.explore.searchEmpty(query: lastSearchedQuery),
          icon: Symbols.search_off_rounded,
          iconSize: 80,
        ),
      );
    }
    return buildResultsSliver((context, index) {
      final item = searchResults[index];
      return FocusableMediaCard(
        key: Key(item.globalKey),
        item: item,
        viewModeOverride: ViewMode.list,
        disableScale: true,
        focusNode: index == 0 ? firstResultFocusNode : null,
        onNavigateLeft: _navigateToSidebar,
        onNavigateUp: index == 0 ? searchFocusNode.requestFocus : null,
      );
    });
  }

  ExploreRowHub? _rowForHub(MediaHub hub) {
    for (final rowHub in _explore.rowHubs) {
      if (rowHub.hub.id == hub.id) return rowHub;
    }
    return null;
  }

  Widget _buildTvToolbar(CatalogSourcesProvider sources) {
    final active = sources.activeSource;
    final foregroundColor = Theme.of(context).colorScheme.onSurface;

    return ToolbarScrim(
      child: Row(
        children: [
          const Spacer(),
          FocusableActionBar(
            key: _actionBarKey,
            onNavigateLeft: _navigateToSidebar,
            onNavigateDown: _tvBrowseRailKey.currentState?.requestFocus,
            onBack: _navigateToSidebar,
            spacing: 4,
            actions: [
              if (active != null && sources.connectedSources.length > 1)
                FocusableAction(
                  debugLabel: 'ExploreSourceSwitcher',
                  onPressed: () => _sourceMenuKey.currentState?.showButtonMenu(focusFirstItem: true),
                  child: _buildSourceSwitcher(
                    sources,
                    active,
                    textStyle: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: foregroundColor, fontWeight: .w600),
                    anchorAlignment: AppMenuAnchorAlignment.end,
                    parentOwnsFocus: true,
                  ),
                ),
              if (active != null)
                FocusableAction(
                  icon: Symbols.search_rounded,
                  iconColor: foregroundColor,
                  tooltip: t.common.search,
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => CatalogSearchScreen(source: active))),
                ),
              // The same door as the redesign's submenu entry. The stage has
              // nothing to do with which theme is on, and one that could only
              // be found under "Ocker" would read as a feature that vanished.
              //
              // Named, unlike its neighbours. Search and Refresh are things
              // this page does to itself and a glyph says them; the stage is
              // somewhere else to go, and an unlabelled film strip beside the
              // source switcher was not read as one.
              FocusableAction(
                debugLabel: 'ExploreTrailerStage',
                onPressed: _openTrailerStage,
                tooltip: t.trailerStage.title,
                child: InkWell(
                  onTap: _openTrailerStage,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: .min,
                      children: [
                        AppIcon(Symbols.theaters_rounded, fill: 1, size: 22, color: foregroundColor),
                        const SizedBox(width: 8),
                        Text(
                          t.trailerStage.title,
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(color: foregroundColor, fontWeight: .w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              FocusableAction(
                icon: Symbols.refresh_rounded,
                iconColor: foregroundColor,
                tooltip: t.common.refresh,
                onPressed: () => unawaited(_explore.load()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Open the trailer stage.
  ///
  /// Always through the setup screen: it is the one place that resolves the
  /// libraries and their genres, and it takes itself out of the way when this
  /// run already has a selection.
  void _openTrailerStage() {
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TrailerStageSetupScreen())));
  }

  /// Which country's streaming line-up to ask about. What is on Netflix in
  /// Germany is not what is on Netflix in the US, and TMDB answers per region.
  static String _watchRegion() {
    final country = PlatformDispatcher.instance.locale.countryCode;
    return country == null || country.isEmpty ? 'US' : country.toUpperCase();
  }

  /// Where a rotating row starts reading, fixed for the life of the app.
  ///
  /// Stable while browsing — a row that reshuffles under the cursor is worse
  /// than one that repeats — and different on the next start, which is what
  /// makes "immer mal was Neues" live up to its name.
  static final int _shelfRotation = DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerHour % 20;

  /// A genre, studio or network tile opens its titles; anything else is an
  /// ordinary item the rail should navigate to itself.
  /// A tile opens its own page; anything else is an ordinary title, which the
  /// stacked sections navigate to the way they always did.
  Future<void> _openTappedItem(MediaHub hub, MediaItem item) async {
    if (await _openTileIfTapped(hub, item)) return;
    if (!mounted) return;
    await navigateToMediaItem(context, item);
  }

  Future<bool> _openTileIfTapped(MediaHub hub, MediaItem item) async {
    final source = _explore.activeSource;
    if (source is PlexCatalogSource) {
      final sectionKey = ExploreProvider.sectionKeyOf(item);
      if (sectionKey == null) return false;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlexSectionScreen(title: item.displayTitle, sectionKey: sectionKey, source: source),
        ),
      );
      return true;
    }
    if (source is! SeerrCatalogSource) return false;

    final networkId = ExploreProvider.networkIdOf(item);
    // A network's films: Seerr filters films by studio, never by network, so
    // the film rows go through TMDB's "available at" filter instead. The id
    // for it is asked of the instance and matched by name — it differs per
    // region, and a wrong one would fill the rows with another service's
    // catalog.
    final region = _watchRegion();
    final providerId = networkId == null
        ? null
        : matchWatchProvider(item.displayTitle, await source.watchProviders('movies', region: region));
    if (!mounted) return false;

    final shelves = seerrShelvesFor(
      source: source,
      now: DateTime.now(),
      studioId: ExploreProvider.studioIdOf(item),
      networkId: networkId,
      movieGenreId: ExploreProvider.genreIdOf(item),
      tvGenreId: ExploreProvider.tvGenreIdOf(item),
      movieWatchProviderId: providerId,
      watchRegion: region,
      rotation: _shelfRotation,
    );
    if (shelves.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SeerrShelfScreen(title: item.displayTitle, shelves: shelves),
        ),
      );
      return true;
    }

    return false;
  }

  Widget _buildTvContent(List<ExploreRowHub> rowHubs, CatalogSourcesProvider sources) {
    final tvHubs = [for (final rowHub in rowHubs) rowHub.hub];

    return TvSpotlightScaffold(
      hubs: tvHubs,
      spotlightListenable: _spotlight,
      resolveSpotlight: () => _resolveExploreSpotlight(tvHubs),
      showSpotlightInfo: !_brandFocused,
      resolveClient: (spotlight) => context.tryGetMediaClientForServer(serverIdOrNull(spotlight?.serverId)),
      foreground: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          if (tvHubs.isEmpty && _explore.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (tvHubs.isEmpty && _explore.state == ExploreLoadState.error)
            Center(
              child: ErrorStateWidget(
                message: _explore.errorMessage ?? t.explore.emptyTitle,
                icon: Symbols.error_outline_rounded,
                onRetry: () => unawaited(_explore.load()),
              ),
            )
          else if (tvHubs.isEmpty)
            Center(
              child: EmptyStateWidget(
                message: t.explore.emptyMessage(source: _explore.activeSource?.displayName ?? ''),
                icon: Symbols.explore_rounded,
              ),
            ),
          if (tvHubs.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TvBrowseRail(
                key: _tvBrowseRailKey,
                hubs: tvHubs,
                focusMemory: _hubFocusMemory,
                iconForHub: (hub, _) => _rowIcon(_rowForHub(hub)?.row),
                onFocusedItemChanged: _setSpotlightItem,
                onActivateItem: _openTileIfTapped,
                loadMoreItems: (hub) {
                  final rowHub = _rowForHub(hub);
                  return rowHub == null ? () => Future.value(hub.items) : () => _explore.loadAllForHub(rowHub);
                },
                onNavigateUp: isOckerLayout(context)
                    ? _navigateToSidebar
                    : _actionBarKey.currentState?.requestFocusOnFirst,
                onNavigateToSidebar: _navigateToSidebar,
                onBack: _navigateToSidebar,
                tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
              ),
            ),
          // See discover_screen: the redesign keeps these behind the word in
          // the header, so the screen does not draw them a second time.
          if (!isOckerLayout(context)) TvToolbarOverlay(child: _buildTvToolbar(sources)),
        ],
      ),
    );
  }
}
