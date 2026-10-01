import 'dart:async';
import '../media/catalog_item_ref.dart';
import '../media/ids.dart';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../media/library_query.dart';
import '../navigation/main_screen_scope.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../media/media_sort.dart';
import '../services/settings_service.dart';
import '../widgets/settings_builder.dart';
import '../widgets/system_bottom_inset.dart';
import '../utils/app_logger.dart';
import '../utils/continuation_pagination_coordinator.dart';
import '../utils/error_message_utils.dart';
import '../utils/platform_detector.dart';
import '../utils/media_server_http_client.dart';
import '../utils/plex_library_section_utils.dart';
import '../utils/provider_extensions.dart';
import '../widgets/focusable_media_card.dart';
import '../widgets/media_card_sliver_layout.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/loading_indicator_box.dart';
import '../widgets/overlay_sheet.dart';
import '../focus/focusable_action_bar.dart';
import '../focus/key_event_utils.dart';
import '../mixins/grid_focus_node_mixin.dart';
import '../mixins/paginated_item_loader.dart';
import 'libraries/sort_bottom_sheet.dart';
import 'libraries/content_state_builder.dart';
import '../mixins/refreshable.dart';
import '../i18n/strings.g.dart';
import 'focusable_detail_screen_mixin.dart';
import '../redesign/ocker_browse_page.dart';
import '../redesign/ocker_skin.dart';
import '../widgets/focusable_tab_chip.dart';
import '../utils/media_navigation_helper.dart';

/// Screen to display full content of a recommendation hub
class HubDetailScreen extends StatefulWidget {
  final MediaHub hub;
  final Future<List<MediaItem>> Function()? loadItems;

  /// A loader that serves one page at a time, for a list too long to pull down
  /// in one go — a Seerr genre runs to thousands of titles. [start] is an item
  /// offset and [size] the number wanted; the returned `totalCount` is what
  /// the grid pages towards. Takes precedence over [loadItems].
  final Future<LibraryPage<MediaItem>> Function(int start, int size)? loadPage;

  /// How many items one [loadPage] call fetches. Match it to the page size the
  /// endpoint actually serves — asking for a multiple means several requests
  /// before anything appears.
  final int? pageSize;
  final bool isInContinueWatching;
  final bool usesContinueWatchingAction;
  final VoidCallback? onRemoveFromContinueWatching;

  /// True when the screen is a navigation destination rather than a pushed
  /// route: it owns no route to pop, so the back affordance and the
  /// pop-on-back path are both dropped. Back still leaves the grid for the
  /// app bar, which is where a D-pad user expects it to go.
  final bool isEmbedded;

  /// Draw the redesign's panel-and-grid page whenever the "Ocker" look is on,
  /// even where the layout is otherwise the app's own.
  ///
  /// The watchlist asks for this and nothing else does. It is one long list
  /// with nothing above it and no shape of its own to lose, so the panel suits
  /// it in either variant — where a hub's "see all" page, opened from a row,
  /// belongs to the arrangement its variant chose.
  ///
  /// Not on a phone or tablet, which wear the look without the layout: a
  /// panel beside the posters is a television's arrangement.
  final bool ockerPageInAnyLayout;

  /// Under the redesign: which list this is, over the right of the grid
  /// ("Merkliste · Plex"). See [OckerGridFilterBand.location].
  final String? ockerLocation;

  /// Replaces the hub title in the app bar. An embedded host uses it to put
  /// its own chrome — a source switcher, say — where the title would sit.
  final Widget? titleOverride;

  /// Where LEFT out of the app bar actions goes. A host that puts focusable
  /// chrome in [titleOverride] passes the hop into it, so the D-pad can reach
  /// what it placed there.
  final VoidCallback? onAppBarNavigateLeft;

  /// Which of the loaded items the grid shows. Applied on every path that
  /// fills the grid, so a host can narrow the list without refetching it —
  /// pass a new closure and the grid re-filters what it already has.
  final bool Function(MediaItem item)? itemFilter;

  /// Host actions placed left of the grid's own sort action.
  final List<FocusableAction> hostAppBarActions;

  const HubDetailScreen({
    super.key,
    required this.hub,
    this.loadItems,
    this.loadPage,
    this.pageSize,
    this.isInContinueWatching = false,
    bool? usesContinueWatchingAction,
    this.onRemoveFromContinueWatching,
    this.isEmbedded = false,
    this.ockerPageInAnyLayout = false,
    this.ockerLocation,
    this.titleOverride,
    this.onAppBarNavigateLeft,
    this.itemFilter,
    this.hostAppBarActions = const [],
  }) : usesContinueWatchingAction = usesContinueWatchingAction ?? isInContinueWatching;

  @override
  State<HubDetailScreen> createState() => HubDetailScreenState();
}

class HubDetailScreenState extends State<HubDetailScreen>
    with Refreshable, GridFocusNodeMixin, FocusableDetailScreenMixin, PaginatedItemLoader<MediaItem, HubDetailScreen> {
  static const int _defaultPageSize = 200;

  int get _pageSize => widget.pageSize ?? _defaultPageSize;

  /// How many pages the screen may pull on its own to fill a list too short
  /// to scroll. Scroll metrics lag the items they describe by a frame or
  /// more, so a chain that trusts them alone reads "still not full" long
  /// after it is and runs down a whole genre. Past this, travelling is what
  /// loads more — which is what the scroll listener is for.
  static const int _autoFillPageLimit = 3;
  int _autoFillPages = 0;

  final GlobalKey<OckerBrowsePageState> _ockerPageKey = GlobalKey();
  List<MediaItem> _items = [];
  List<MediaItem> _filteredItems = [];
  List<MediaSort> _sortOptions = [];
  MediaSort? _selectedSort;
  bool _isSortDescending = false;
  bool _isLoading = false;
  String? _errorMessage;
  bool _replaceContinuationItems = false;
  bool _usesPaginatedLoader = false;

  late final ContinuationPaginationCoordinator<MediaItem> _continuation = ContinuationPaginationCoordinator<MediaItem>(
    loadPage: _fetchContinuationPage,
    onPage: _applyContinuationPage,
    onStateChanged: _handleContinuationStateChanged,
    onError: (error, stackTrace) =>
        appLogger.w('Failed to finish loading hub content', error: error, stackTrace: stackTrace),
  );

  /// Key for getting a context below OverlaySheetHost
  final GlobalKey _overlayChildKey = GlobalKey();
  final FocusNode _continuationRetryFocusNode = FocusNode(debugLabel: 'hub_continuation_retry');

  @override
  bool get hasItems => _filteredItems.isNotEmpty;

  @override
  List<FocusableAction> getAppBarActions() {
    return [
      ...widget.hostAppBarActions,
      FocusableAction(icon: Symbols.swap_vert_rounded, tooltip: t.libraries.sort, onPressed: _showSortBottomSheet),
    ];
  }

  /// Override to add bounds check for filtered items (sorting can change item order)
  @override
  void navigateToGrid() {
    // Down out of the chrome row under the redesign. Its grid owns its own
    // focus nodes, so the mixin's card-key search finds nothing and DOWN did
    // nothing at all — with the provider switcher gone from that row, the
    // filters were then a corner with no way out. Same delegation as
    // [focusFromHostTab].
    if (_ockerPageKey.currentState case final page?) {
      if (!hasItems) return;
      setState(() {
        isAppBarFocused = false;
      });
      page.focusGridFromBand();
      return;
    }
    if (!hasItems) return;

    final targetIndex = shouldRestoreGridFocus && lastFocusedGridIndex! < _filteredItems.length
        ? lastFocusedGridIndex!
        : 0;

    setState(() {
      isAppBarFocused = false;
    });

    _focusNodeForIndex(targetIndex).requestFocus();
  }

  FocusNode _focusNodeForIndex(int index) => focusNodeForIndex(
    index,
    firstItemFocusNode,
    prefix: 'hub_detail_item',
    itemIdentity: _filteredItems[index].globalKey,
  );

  /// Land focus in the grid, for an embedded host whose tab has just become
  /// the visible one. The pushed-route case does this itself in [initState].
  void focusFromHostTab() {
    // Ocker's grid owns its own nodes, so the mixin's card-key search has
    // nothing to find; the page is asked directly.
    if (_ockerPageKey.currentState case final page?) {
      page.focusFirstItem();
      return;
    }
    autoFocusFirstItemAfterLoad();
  }

  /// Move focus into the app bar actions, for a host handing focus back.
  void focusAppBarFromHost() => navigateToAppBar();

  /// UP out of the grid under the redesign: the filters over its top left,
  /// or — where there are none — the rail, on a destination.
  void _exitUpBesideRail() {
    if (getAppBarActions().isNotEmpty) {
      navigateToAppBar();
      return;
    }
    if (widget.isEmbedded) MainScreenFocusScope.focusSidebarOf(context);
  }

  /// Left of the first filter lies the host's word, where it has one. Under
  /// the redesign the filters start the page at its left edge, and LEFT is
  /// the rail — on a destination; a page pushed over the shell has none.
  @override
  VoidCallback? get appBarNavigateLeft =>
      widget.onAppBarNavigateLeft ??
      (isOckerLayout(context) && widget.isEmbedded ? () => MainScreenFocusScope.focusSidebarOf(context) : null);

  @override
  void handleAppBarBack() {
    // No route of its own to pop; BACK belongs to the sidebar instead.
    if (widget.isEmbedded) {
      MainScreenFocusScope.focusSidebarOf(context);
      return;
    }
    super.handleAppBarBack();
  }

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_handleScrolled);
    _items = widget.hub.items;
    final filter = widget.itemFilter;
    _filteredItems = filter == null
        ? widget.hub.items
        : [
            for (final item in _items)
              if (filter(item)) item,
          ];
    if (widget.hub.more) {
      _loadMoreItems();
    }
    _loadSorts();
    // A pushed route owns the screen the moment it opens, so grabbing focus is
    // right there. A tab does not: every tab in the IndexedStack is built up
    // front, so an embedded screen that auto-focused would pull focus out of
    // whichever tab the user is actually looking at — leaving a focus ring
    // stranded on the visible page. The host focuses it when its tab is shown.
    if (!widget.isEmbedded) autoFocusFirstItemAfterLoad();
  }

  /// A host that changed its filter passes a new closure; the grid narrows
  /// what it already holds rather than fetching the list again.
  @override
  void didUpdateWidget(HubDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemFilter != oldWidget.itemFilter) _applySort();
  }

  @override
  void dispose() {
    scrollController.removeListener(_handleScrolled);
    disposePagination();
    _continuation.dispose();
    _continuationRetryFocusNode.dispose();
    disposeFocusResources();
    super.dispose();
  }

  Future<void> _loadSorts() async {
    List<MediaSort> sorts = const [];
    try {
      // Hub ids can have various formats:
      // - /hubs/sections/1/... (Plex)
      // - /library/sections/1/all?... (Plex)
      // - /hubs/home/recentlyAdded?type=2&sectionID=1 (Plex home hubs — id in query)
      // - home.recent / library.<id>.continue (Jellyfin synthesized)
      // - continue_watching / explore:… (aggregated and catalog rows; no server)
      // Only a Plex library-scoped key names a section whose sort options can
      // be fetched; every other shape falls back to the default sorts by design.
      final hubKey = widget.hub.id;
      final sectionId = plexLibrarySectionIdFromString(hubKey);
      final serverId = widget.hub.serverId;
      if (sectionId == null) {
        appLogger.d('Hub $hubKey has no library section; using default sort options');
      } else if (serverId == null) {
        appLogger.w('Hub $hubKey names section $sectionId but has no serverId; using default sort options');
      } else {
        final client = context.tryGetMediaClientForServer(ServerId(serverId));
        sorts = client == null ? const <MediaSort>[] : await client.fetchSortOptions('$sectionId');
        appLogger.d('Loaded ${sorts.length} sorts for section $sectionId');
      }
    } catch (e, stackTrace) {
      appLogger.e('Failed to load sorts', error: e, stackTrace: stackTrace);
    }
    if (!mounted) return;
    // Sorting runs client-side over the loaded items, so offer only the
    // section sorts it can honor instead of ones that would silently fall
    // back to title order.
    final supported = [
      for (final sort in sorts)
        if (_comparatorFor(sort.key) != null) sort,
    ];
    setState(() {
      _sortOptions = supported.isNotEmpty ? supported : _getDefaultSortOptions();
    });
  }

  /// Catalog hubs (Explore View All) hold synthesized items with no library
  /// timestamps, so a Date Added sort would silently no-op — offer only the
  /// fields those items carry.
  bool get _isCatalogHub => widget.hub.items.firstOrNull?.isCatalogItem ?? false;

  List<MediaSort> _getDefaultSortOptions() {
    return [
      MediaSort(key: 'titleSort', title: t.hubDetail.title, defaultDirection: 'asc'),
      MediaSort(key: 'year', descKey: 'year:desc', title: t.hubDetail.releaseYear, defaultDirection: 'desc'),
      if (!_isCatalogHub)
        MediaSort(key: 'addedAt', descKey: 'addedAt:desc', title: t.hubDetail.dateAdded, defaultDirection: 'desc'),
      MediaSort(key: 'rating', descKey: 'rating:desc', title: t.hubDetail.rating, defaultDirection: 'desc'),
    ];
  }

  /// Orders items by the field a sort [key] names — the default sorts' keys
  /// and the Plex section sort keys alike — or null for a key naming nothing
  /// the items carry (Plex's resolution, bitrate, random or latest-episode
  /// sorts), which [_loadSorts] leaves out of the options.
  static Comparator<MediaItem>? _comparatorFor(String key) {
    Comparator<MediaItem> by(Comparable<Object> Function(MediaItem item) value) =>
        (a, b) => value(a).compareTo(value(b));
    return switch (key) {
      'titleSort' || 'title' => by((item) => (item.titleSort ?? item.title ?? '').toLowerCase()),
      'addedAt' => by((item) => item.addedAt ?? 0),
      'year' => by((item) => item.year ?? 0),
      // ISO dates order lexically; an undated item sorts by its year.
      'originallyAvailableAt' => by((item) => item.originallyAvailableAt ?? '${item.year ?? ''}'),
      'rating' => by((item) => item.rating ?? 0),
      'userRating' => by((item) => item.userRating ?? 0),
      'contentRating' => by((item) => item.contentRating ?? ''),
      'duration' => by((item) => item.durationMs ?? 0),
      'viewOffset' => by((item) => item.viewOffsetMs ?? 0),
      'viewCount' => by((item) => item.viewCount ?? 0),
      'lastViewedAt' => by((item) => item.lastViewedAt ?? 0),
      'unviewedLeafCount' => by((item) => item.unwatchedCount ?? 0),
      _ => null,
    };
  }

  void _applySort() {
    setState(() {
      final filter = widget.itemFilter;
      _filteredItems = filter == null
          ? List.from(_items)
          : [
              for (final item in _items)
                if (filter(item)) item,
            ];

      final selectedSort = _selectedSort;
      if (selectedSort != null) {
        final compare = _comparatorFor(selectedSort.key) ?? _comparatorFor('titleSort')!;
        _filteredItems.sort((a, b) => _isSortDescending ? compare(b, a) : compare(a, b));
      }
    });
    _remapFocusToFocusedItem();
  }

  void _showSortBottomSheet() {
    final overlayContext = _overlayChildKey.currentContext ?? context;
    MediaSort? pendingSort = _selectedSort;
    bool pendingDescending = _isSortDescending;
    bool pendingCleared = false;
    OverlaySheetController.of(overlayContext)
        .show(
          builder: (context) => SortBottomSheet(
            sortOptions: _sortOptions,
            selectedSort: _selectedSort,
            isSortDescending: _isSortDescending,
            onSortChanged: (sort, descending) {
              pendingSort = sort;
              pendingDescending = descending;
              pendingCleared = false;
            },
            onClear: () {
              pendingSort = null;
              pendingDescending = false;
              pendingCleared = true;
            },
          ),
        )
        .then((_) {
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (pendingCleared) {
              _selectedSort = null;
              _isSortDescending = false;
              _applySort();
            } else if (pendingSort != null &&
                (pendingSort!.key != _selectedSort?.key || pendingDescending != _isSortDescending)) {
              _selectedSort = pendingSort;
              _isSortDescending = pendingDescending;
              _applySort();
            }
          });
        });
  }

  bool _shouldUsePaginatedLoader(MediaServerClient client) =>
      client.backend.usesMediaBrowserApi && widget.hub.id.endsWith('.recent');

  @override
  Future<LibraryPage<MediaItem>> fetchPage(int start, int size, AbortController? abort) async {
    if (widget.loadPage case final load?) return load(start, size);
    final serverId = widget.hub.serverId;
    final client = serverId == null ? null : context.tryGetMediaClientForServer(ServerId(serverId));
    if (client == null) throw StateError('No media client available for paginated hub');
    return client.fetchMoreHubItemsPage(widget.hub.id, start: start, size: size, abort: abort);
  }

  @override
  void onPageLoaded(int start, List<MediaItem> items) {
    if (!_usesPaginatedLoader || start == 0 || !mounted) return;
    _replaceItems(List.of(_items)..addAll(items));
    _scheduleNextHubPageCheck();
  }

  @override
  void onPaginationStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadMoreItems() async {
    if (_isLoading) return;

    final serverId = widget.hub.serverId;
    final loader = widget.loadItems;
    final pagedLoader = widget.loadPage;
    if (loader == null && pagedLoader == null && serverId == null) {
      appLogger.w('Hub has no serverId; cannot load more items for ${widget.hub.id}');
      return;
    }

    final client = serverId == null ? null : context.tryGetMediaClientForServer(ServerId(serverId));
    final usesCustomLoader = loader != null && pagedLoader == null;
    _usesPaginatedLoader =
        pagedLoader != null || (!usesCustomLoader && client != null && _shouldUsePaginatedLoader(client));

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _autoFillPages = 0;
      if (_usesPaginatedLoader) resetPaginationState();
    });

    try {
      List<MediaItem> items = const [];
      var totalCount = 0;
      var loadedCount = 0;
      var initialPageApplied = true;
      final applied = await _continuation.runNewGeneration(() async {
        if (_usesPaginatedLoader) {
          final result = await loadInitialPageWithStatus(_pageSize);
          initialPageApplied = result.applied;
          if (!result.applied) return;
          items = result.page.items;
          totalCount = result.page.totalCount;
          loadedCount = result.page.items.length;
        } else if (loader == null) {
          final page = client == null
              ? const LibraryPage<MediaItem>(items: [], totalCount: 0)
              : await client.fetchMoreHubItemsPage(widget.hub.id, start: 0, size: _pageSize);
          items = _applySectionFilter(page.items);
          totalCount = page.totalCount;
          loadedCount = page.items.length;
        } else {
          items = _applySectionFilter(await loader());
          totalCount = items.length;
          loadedCount = items.length;
        }
      });

      if (!mounted || !applied || !initialPageApplied) return;
      setState(() {
        _items = List.of(items);
        _filteredItems = List.of(items);
        _isLoading = false;
      });

      _applySort();
      if (!usesCustomLoader && !_usesPaginatedLoader && client != null && loadedCount < totalCount) {
        _replaceContinuationItems = !client.backend.usesMediaBrowserApi;
        if (_replaceContinuationItems) {
          _continuation.setContinuation(startIndex: 0, totalCount: 1);
        } else {
          _continuation.setContinuation(startIndex: loadedCount, totalCount: totalCount);
        }
        unawaited(_continuation.loadRemaining());
      } else if (_usesPaginatedLoader && loadedCount < totalCount) {
        _scheduleNextHubPageCheck();
      }

      appLogger.d('Loaded ${items.length} items for hub: ${widget.hub.title}');
    } catch (e, stackTrace) {
      final message = localizedLoadErrorMessage(e, stackTrace, context: widget.hub.title);
      if (!mounted) return;
      setState(() {
        _errorMessage = message;
        _isLoading = false;
      });
    }
  }

  Future<ContinuationPage<MediaItem>> _fetchContinuationPage(int startIndex) async {
    final serverId = widget.hub.serverId;
    final client = serverId == null ? null : context.tryGetMediaClientForServer(ServerId(serverId));
    if (client == null) throw StateError('No media client available for hub continuation');

    if (_replaceContinuationItems) {
      final items = _applySectionFilter(await client.fetchMoreHubItems(widget.hub.id));
      if (items.isEmpty && _items.isNotEmpty) {
        throw StateError('Hub continuation returned no items');
      }
      return ContinuationPage(items: items, totalCount: 1, consumedCount: 1);
    }

    final page = await client.fetchMoreHubItemsPage(widget.hub.id, start: startIndex, size: _pageSize);
    return ContinuationPage(
      items: _applySectionFilter(page.items),
      totalCount: page.totalCount,
      consumedCount: page.items.length,
    );
  }

  void _applyContinuationPage(ContinuationPage<MediaItem> page) {
    if (!mounted) return;
    _replaceItems(_replaceContinuationItems ? List.of(page.items) : (List.of(_items)..addAll(page.items)));
  }

  /// Swap in the merged item list and re-derive the sorted view from it.
  void _replaceItems(List<MediaItem> items) {
    setState(() {
      _items = items;
      _filteredItems = List.of(_items);
    });
    _applySort();
  }

  /// Travelling re-arms the fill: the viewer is asking for what comes next,
  /// and by now the metrics describe what is actually on screen.
  void _handleScrolled() {
    _autoFillPages = 0;
    _maybeLoadNextHubPage();
  }

  void _scheduleNextHubPageCheck() {
    if (_autoFillPages >= _autoFillPageLimit) return;
    _autoFillPages++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadNextHubPage();
    });
  }

  /// Whether the offset-paged loader has another page to request.
  bool get _canRequestNextHubPage =>
      _usesPaginatedLoader && loadedItems.length < totalSize && !isPaginationLoading && paginationError == null;

  void _maybeLoadNextHubPage() {
    if (!_canRequestNextHubPage || !scrollController.hasClients) return;
    final position = scrollController.position;
    if (position.extentAfter <= position.viewportDimension) {
      _requestNextHubPage();
    }
  }

  void _requestNextHubPage() {
    if (!_canRequestNextHubPage) return;
    ensureIndexLoaded(loadedItems.length, pageSize: _pageSize);
  }

  void _handleGridItemFocusChange(int index, bool hasFocus, {required bool isLastRow}) {
    trackGridItemFocus(index, hasFocus);
    if (hasFocus && isLastRow) _requestNextHubPage();
  }

  /// Reconcile all realized items, including references captured under a cover.
  void _remapFocusToFocusedItem() {
    final indices = <String, int>{for (var i = 0; i < _filteredItems.length; i++) _filteredItems[i].globalKey: i};
    reconcileGridFocusNodes(indices);
  }

  void _handleContinuationStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _retryHubContinuation() {
    if (_usesPaginatedLoader) {
      ensureIndexLoaded(loadedItems.length, pageSize: _pageSize);
    } else {
      unawaited(_continuation.retry());
    }
  }

  List<MediaItem> _applySectionFilter(List<MediaItem> items) {
    final sectionFilter = int.tryParse(widget.hub.libraryId ?? '');
    if (sectionFilter == null) return items;
    return items.where((item) => int.tryParse(item.libraryId ?? '') == sectionFilter).toList();
  }

  Future<void> _handleItemRefresh(MediaItem source) async {
    final serverId = source.serverId;
    if (serverId == null) return;

    try {
      final updated = await context.tryGetMediaClientForServer(ServerId(serverId))?.fetchItem(source.id);
      if (updated == null || !mounted) return;
      setState(() {
        final currentItemIndex = _items.indexWhere((item) => item.globalKey == source.globalKey);
        if (currentItemIndex != -1) _items[currentItemIndex] = updated;
        final currentFilteredIndex = _filteredItems.indexWhere((item) => item.globalKey == source.globalKey);
        if (currentFilteredIndex != -1) _filteredItems[currentFilteredIndex] = updated;
      });
      if (_selectedSort != null) _applySort();
    } catch (e) {
      appLogger.d('Item refresh skipped for: ${source.globalKey}', error: e);
    }
  }

  void _handleRemoveFromContinueWatching() {
    widget.onRemoveFromContinueWatching?.call();
    unawaited(_loadMoreItems());
  }

  Object? get _pageLoadError => _usesPaginatedLoader ? paginationError : _continuation.error;
  bool get _isLoadingPage => _usesPaginatedLoader ? isPaginationLoading : _continuation.isLoading;

  @override
  void refresh() {
    _loadMoreItems();
  }

  Widget _buildOckerPage(BuildContext context) {
    final switcher = widget.titleOverride;
    return OverlaySheetHost(
      canPop: !widget.isEmbedded && PlatformDetector.isHandheldIOS(context),
      onSystemBack: () {
        if (BackKeyCoordinator.consumeIfHandled()) return;
        if (handleBackNavigation() && mounted && !widget.isEmbedded) Navigator.pop(context);
      },
      child: OckerBrowsePage(
        key: _ockerPageKey,
        title: widget.hub.title,
        items: _filteredItems,
        totalCount: widget.hub.size > _filteredItems.length ? widget.hub.size : null,
        resolveClient: (item) => item?.serverId == null
            ? context.tryGetMediaClientForServer(null)
            : context.tryGetMediaClientForServer(ServerId(item!.serverId!)),
        // Up out of the grid goes to the row above it first: the provider
        // switcher sits there, and jumping straight past it to the navigation
        // would make it unreachable by the D-pad.
        onExitToHeader: _exitUpBesideRail,
        // A row before the end of the grid. Under a paged loader that means
        // the next page; without one there is nothing further to fetch and
        // the first load is all there ever was.
        onReachedEnd: _usesPaginatedLoader ? _requestNextHubPage : _loadMoreItems,
        // Left out of the first column reaches the rail — from a destination;
        // a page pushed over the shell has no rail and swallows it.
        onExitLeft: widget.isEmbedded ? () => MainScreenFocusScope.focusSidebarOf(context) : null,
        // A chip strip when the host gave one — the watchlist's provider
        // switcher. A plain title would only repeat the heading below it.
        header: switcher is TabChipStrip ? switcher : null,
        // A destination the header already names does not need naming
        // again; a page pushed on top of one does.
        showHeading: !widget.isEmbedded,
        // The watchlist, the one page embedded as a destination, has no count
        // at its foot; see [OckerBrowsePage.showCount].
        showCount: !widget.isEmbedded,
        location: widget.ockerLocation,
        filters: buildFocusableAppBarActions(),
        emptyState: Center(child: Text(_items.isEmpty ? t.hubDetail.noItemsFound : t.libraries.noItemsMatchFilters)),
        onPlay: (_, item) => unawaited(
          navigateToMediaItem(
            context,
            item,
            onRefresh: _handleItemRefresh,
            playDirectly: widget.usesContinueWatchingAction,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The redesign draws every list of titles the same way: the titles are a
    // quiet grid, and the panel beside it describes whatever holds focus.
    // Same items, same filters, same way of opening them — this screen is the
    // one the watchlist, the search results and every hub page run through, so
    // one branch reaches all of them. See lib/redesign/.
    if (isOckerLayout(context) ||
        (widget.ockerPageInAnyLayout && isOcker(context) && !PlatformDetector.isMobile(context))) {
      return _buildOckerPage(context);
    }

    return PrimaryScrollController(
      controller: scrollController,
      child: OverlaySheetHost(
        // Host owns sheet + system back: a back with a sheet open closes it;
        // otherwise focus the app bar first, then pop (handleBackNavigation).
        // canPop preserves the iOS interactive swipe-back.
        canPop: !widget.isEmbedded && PlatformDetector.isHandheldIOS(context),
        onSystemBack: () {
          if (BackKeyCoordinator.consumeIfHandled()) return;
          if (handleBackNavigation() && mounted && !widget.isEmbedded) Navigator.pop(context);
        },
        child: Scaffold(
          key: _overlayChildKey,
          body: CustomScrollView(
            primary: true,
            // Unclipped so a focused card's glow can reach past the
            // viewport's edge — except under "Ocker", which has no glow: its
            // focus ring is a hairline 5 px out, and leaving the view unclipped
            // there only lets the top row paint over the chrome above it.
            clipBehavior: isOcker(context) ? Clip.hardEdge : Clip.none,
            slivers: [
              CustomAppBar(
                title: widget.titleOverride ?? Text(widget.hub.title),
                pinned: true,
                automaticallyImplyLeading: !widget.isEmbedded,
                actions: buildFocusableAppBarActions(),
              ),
              if (_errorMessage != null)
                SliverErrorState(message: _errorMessage!, onRetry: _loadMoreItems)
              else if (_filteredItems.isEmpty && _isLoading)
                LoadingIndicatorBox.sliver
              else if (_filteredItems.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    // "Nothing here" and "nothing left after filtering" are
                    // different answers, and only the second one tells the
                    // viewer what to undo.
                    child: Text(_items.isEmpty ? t.hubDetail.noItemsFound : t.libraries.noItemsMatchFilters),
                  ),
                )
              else
                SettingsBuilder(
                  prefs: const [
                    SettingsService.viewMode,
                    SettingsService.episodePosterMode,
                    SettingsService.libraryDensity,
                    SettingsService.tvFullCardLayout,
                  ],
                  builder: (context) {
                    final svc = SettingsService.instance;
                    final viewMode = svc.read(SettingsService.viewMode);
                    final episodePosterMode = svc.read(SettingsService.episodePosterMode);
                    final libraryDensity = svc.read(SettingsService.libraryDensity);
                    final fullCardLayout = PlatformDetector.isTV() && svc.read(SettingsService.tvFullCardLayout);

                    final hasEpisodes = _filteredItems.any((item) => item.usesWideAspectRatio(episodePosterMode));
                    final hasNonEpisodes = _filteredItems.any((item) => !item.usesWideAspectRatio(episodePosterMode));

                    final isMixedHub = hasEpisodes && hasNonEpisodes;

                    final isEpisodeOnlyHub = hasEpisodes && !hasNonEpisodes;

                    final useWideLayout =
                        episodePosterMode == EpisodePosterMode.episodeThumbnail && (isEpisodeOnlyHub || isMixedHub);

                    final isSquareHub =
                        _filteredItems.isNotEmpty &&
                        _filteredItems.every((item) => item.cardShape(episodePosterMode) == CardShape.square);

                    return MediaCardSliverLayout(
                      viewMode: viewMode,
                      itemCount: _filteredItems.length,
                      findChildIndexCallback: (key) {
                        final id = (key as ValueKey<String>).value;
                        final index = _filteredItems.indexWhere((item) => item.globalKey == id);
                        return index < 0 ? null : index;
                      },
                      density: libraryDensity,
                      padding: const EdgeInsets.all(8),
                      useWideAspectRatio: useWideLayout,
                      fullBleedImage: fullCardLayout,
                      shape: isSquareHub ? CardShape.square : null,
                      itemBuilder: (context, position) {
                        final index = position.index;
                        final item = _filteredItems[index];
                        final focusNode = _focusNodeForIndex(index);

                        return FocusableMediaCard(
                          // Keyed by item, not by slot: a re-sort must move
                          // the element with its item instead of silently
                          // updating it with a different one. Aggregated
                          // hubs mix servers, so the id alone can collide.
                          key: Key(item.globalKey),
                          focusNode: focusNode,
                          item: item,
                          disableScale: position.disableScale,
                          onRefresh: _handleItemRefresh,
                          onRemoveFromContinueWatching: widget.isInContinueWatching
                              ? _handleRemoveFromContinueWatching
                              : null,
                          isInContinueWatching: widget.isInContinueWatching,
                          usesContinueWatchingAction: widget.usesContinueWatchingAction,
                          onNavigateUp: position.isFirstRow ? navigateToAppBar : null,
                          onNavigateDown:
                              _pageLoadError != null && position.index >= position.itemCount - position.columnCount
                              ? _continuationRetryFocusNode.requestFocus
                              : null,
                          onNavigateLeft: position.isGrid && position.isFirstColumn
                              ? (widget.isEmbedded ? () => MainScreenFocusScope.focusSidebarOf(context) : () {})
                              : null,
                          onBack: handleBackFromContent,
                          onFocusChange: (hasFocus) => _handleGridItemFocusChange(
                            index,
                            hasFocus,
                            isLastRow: position.index >= position.itemCount - position.columnCount,
                          ),
                          mixedHubContext: isMixedHub,
                          fullBleedImage: fullCardLayout && position.isGrid,
                        );
                      },
                    );
                  },
                ),
              if (_filteredItems.isNotEmpty && (_isLoadingPage || _pageLoadError != null))
                ContinuationStatusSliver(
                  error: _pageLoadError,
                  onRetry: _retryHubContinuation,
                  retryFocusNode: _continuationRetryFocusNode,
                  errorContext: widget.hub.title,
                  onNavigateUp: () => _focusNodeForIndex(_filteredItems.length - 1).requestFocus(),
                  onBack: handleBackFromContent,
                ),
              const SliverSystemBottomInset(),
            ],
          ),
        ),
      ),
    );
  }
}
