import 'dart:async';

import 'package:flutter/material.dart';

import '../focus/hub_vertical_navigation.dart';
import '../focus/locked_hub_controller.dart';
import '../media/library_query.dart';
import '../i18n/strings.g.dart';
import '../media/media_hub.dart';
import '../media/ids.dart';
import '../media/media_kind.dart';
import '../media/media_item.dart';
import '../services/catalog/seerr_shelves.dart';
import '../utils/app_logger.dart';
import '../widgets/desktop_app_bar.dart';
import '../utils/hub_icons.dart';
import '../utils/platform_detector.dart';
import '../widgets/hub_section.dart';
import '../utils/provider_extensions.dart';
import '../widgets/tv_browse_rail.dart';
import '../widgets/tv_spotlight_scaffold.dart';
import 'hub_detail_screen.dart';
import 'seerr_filtered_hub_screen.dart';

/// A Seerr studio, network or genre as a page of rows.
///
/// Before this, such a page was one long grid in one order — Seerr's dedicated
/// studio and network routes take nothing but a page number, so there was
/// nothing to tell one shelf from another. The rows here come from the parent
/// discover routes, which carry the studio or network as a filter and leave
/// the sort free.
///
/// Each row shows its first page and ends in "view all", which opens the same
/// query as a paged grid.
class SeerrShelfScreen extends StatefulWidget {
  final String title;
  final List<SeerrShelf> shelves;

  const SeerrShelfScreen({super.key, required this.title, required this.shelves});

  @override
  State<SeerrShelfScreen> createState() => _SeerrShelfScreenState();
}

class _SeerrShelfScreenState extends State<SeerrShelfScreen> {
  final _focusMemory = HubFocusMemory();
  final _spotlight = TvSpotlightController();
  final Map<String, MediaHub> _hubs = {};

  /// One key per shown row, so a press on the D-pad can hand focus to the row
  /// above or below. Without them the page is a set of rows the cursor cannot
  /// leave — left and right work inside the first one and nothing else does.
  final Map<String, GlobalKey<HubSectionState>> _rowKeys = {};
  var _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _spotlight.dispose();
    super.dispose();
  }

  /// Every row's first page at once. A row that comes back empty — a studio
  /// with nothing upcoming, say — is left out rather than shown as an empty
  /// shelf.
  Future<void> _load() async {
    final loaded = await Future.wait([for (final shelf in widget.shelves) _firstPage(shelf)]);
    if (!mounted) return;
    setState(() {
      for (final entry in loaded) {
        if (entry != null) _hubs[entry.id] = entry;
      }
      _loading = false;
    });
  }

  Future<MediaHub?> _firstPage(SeerrShelf shelf) async {
    try {
      final page = await shelf.load(1);
      final items = [for (final item in page.items) item.toMediaItem()];
      if (items.isEmpty) return null;
      return MediaHub(
        id: shelf.id,
        title: shelf.title,
        type: shelf.kind.name,
        items: items,
        size: page.totalResults ?? items.length,
        // Puts the "view all" card at the end of the row, which is the way
        // into the full list for this row's query.
        more: page.hasMore || (page.totalResults ?? 0) > items.length,
      );
    } catch (error, stackTrace) {
      appLogger.d('Seerr shelf ${shelf.id} failed', error: error, stackTrace: stackTrace);
      return null;
    }
  }

  /// The grid behind a row: the same query, a page at a time.
  Future<LibraryPage<MediaItem>> _pageFor(SeerrShelf shelf, int start) async {
    final page = await shelf.load((start ~/ seerrPageSize) + 1);
    final items = [for (final item in page.items) item.toMediaItem()];
    return LibraryPage(
      items: items,
      totalCount: page.totalResults ?? (start + items.length + (page.hasMore ? seerrPageSize : 0)),
      offset: start,
    );
  }

  void _openEverything(SeerrShelf shelf) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SeerrFilteredHubScreen(
            title: widget.title,
            hubKey: shelf.id,
            tabs: [
              for (final tab in shelf.tabs ?? const <SeerrShelf>[])
                SeerrFilterTab(
                  id: tab.kind.name,
                  label: tab.kind == MediaKind.movie ? t.libraries.groupings.movies : t.libraries.groupings.shows,
                  load: (start, size) => _pageFor(tab, start),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Move between rows, the way the home screen does off TV.
  bool _handleVerticalNavigation(List<String> ids, int index, bool isUp) => navigateVerticalHubRows(
    hubCount: ids.length,
    hubIndex: index,
    isUp: isUp,
    requestFocus: (target) => _rowKeys[ids[target]]?.currentState?.requestFocusFromMemory(),
  );

  /// Where a row's "view all" goes: the whole list with its tabs for the
  /// leading row, this row's own query as a paged grid for the rest.
  void _openViewAll(SeerrShelf shelf, MediaHub hub) {
    if (shelf.tabs != null) {
      _openEverything(shelf);
      return;
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              HubDetailScreen(hub: hub, loadPage: (start, size) => _pageFor(shelf, start), pageSize: seerrPageSize),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final shelf in widget.shelves)
        if (_hubs[shelf.id] case final hub?) (shelf: shelf, hub: hub),
    ];

    if (_loading) {
      return Scaffold(
        body: CustomScrollView(
          slivers: [
            CustomAppBar(title: Text(widget.title), pinned: true),
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
          ],
        ),
      );
    }

    // The same widget the home screen uses on each form factor, so the cards
    // are the size and spacing the viewer already knows: the TV rail there,
    // stacked sections here.
    if (PlatformDetector.isTV()) return _buildTvRail(rows);
    return _buildSections(rows);
  }

  /// The TV layout the home and Explore screens use: the focused title fills
  /// the top with its backdrop, logo and description, and the rows sit in a
  /// band along the bottom.
  ///
  /// Not decoration — the rail measures itself against that band. Put on its
  /// own in a plain scaffold it lays its rows out from the top and leaves the
  /// rest of the screen empty, which is exactly what it did before this.
  Widget _buildTvRail(List<({SeerrShelf shelf, MediaHub hub})> rows) {
    final hubs = [for (final row in rows) row.hub];
    final byId = {for (final row in rows) row.hub.id: row.shelf};

    return Scaffold(
      body: TvSpotlightScaffold(
        hubs: hubs,
        spotlightListenable: _spotlight,
        resolveSpotlight: () => _spotlight.resolve(hubs),
        resolveClient: (spotlight) => context.tryGetMediaClientForServer(serverIdOrNull(spotlight?.serverId)),
        foreground: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TvBrowseRail(
                hubs: hubs,
                focusMemory: _focusMemory,
                iconForHub: (hub, _) => hubIconFor(hub),
                onFocusedItemChanged: _spotlight.select,
                trailingForHub: (_) => TvRailTrailing.viewAll,
                onViewAll: (hub) {
                  if (byId[hub.id] case final shelf?) _openViewAll(shelf, hub);
                },
                onBack: () => Navigator.of(context).maybePop(),
                tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
              ),
            ),
            TvToolbarOverlay(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: BackButton(onPressed: () => Navigator.of(context).maybePop()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSections(List<({SeerrShelf shelf, MediaHub hub})> rows) {
    final ids = [for (final row in rows) row.shelf.id];
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          CustomAppBar(title: Text(widget.title), pinned: true),
          for (var index = 0; index < rows.length; index++)
            SliverToBoxAdapter(
              child: HubSection(
                key: _rowKeys.putIfAbsent(rows[index].shelf.id, GlobalKey<HubSectionState>.new),
                hub: rows[index].hub,
                focusMemory: _focusMemory,
                icon: hubIconFor(rows[index].hub),
                onVerticalNavigation: (isUp) => _handleVerticalNavigation(ids, index, isUp),
                onViewAll: () => _openViewAll(rows[index].shelf, rows[index].hub),
                loadPage: (start, size) => _pageFor(rows[index].shelf, start),
                pageSize: seerrPageSize,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
