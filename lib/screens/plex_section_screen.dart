import 'dart:async';

import 'package:flutter/material.dart';

import '../focus/hub_vertical_navigation.dart';
import '../focus/locked_hub_controller.dart';
import '../i18n/strings.g.dart';
import '../media/media_hub.dart';
import '../media/ids.dart';
import '../services/catalog/catalog_source.dart';
import '../services/catalog/plex_catalog_source.dart';
import '../utils/app_logger.dart';
import '../utils/error_message_utils.dart';
import '../utils/hub_icons.dart';
import '../utils/platform_detector.dart';
import '../utils/provider_extensions.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/hub_section.dart';
import '../widgets/tv_browse_rail.dart';
import '../widgets/tv_spotlight_scaffold.dart';
import 'hub_detail_screen.dart';
import 'libraries/content_state_builder.dart';

/// One Discover destination — a streaming service, a genre, an award — as a
/// page of rows.
///
/// Discover keeps such a section's titles in shelves of its own: what is new
/// there, what it recommends. Plex's own client shows them that way, and
/// poured into a single grid they lose the one thing that ordered them.
class PlexSectionScreen extends StatefulWidget {
  const PlexSectionScreen({super.key, required this.title, required this.sectionKey, required this.source});

  final String title;

  /// The Discover path this page is built from.
  final String sectionKey;
  final PlexCatalogSource source;

  @override
  State<PlexSectionScreen> createState() => _PlexSectionScreenState();
}

class _PlexSectionScreenState extends State<PlexSectionScreen> {
  final _focusMemory = HubFocusMemory();
  final _spotlight = TvSpotlightController();
  final Map<String, GlobalKey<HubSectionState>> _rowKeys = {};

  List<MediaHub> _hubs = const [];
  String? _error;
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

  Future<void> _load() async {
    try {
      final hubs = await widget.source.fetchSectionHubs(widget.sectionKey);
      if (!mounted) return;
      setState(() {
        _hubs = [for (final hub in hubs) _toMediaHub(hub)];
        _loading = false;
      });
    } catch (error, stackTrace) {
      appLogger.w('Plex: shelves of ${widget.sectionKey} failed', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _error = localizedLoadErrorMessage(error, stackTrace, context: widget.title);
        _loading = false;
      });
    }
  }

  MediaHub _toMediaHub(CatalogHub hub) => MediaHub(
    id: 'plex:section:${widget.sectionKey}:${hub.id}',
    identifier: hub.id,
    title: hub.title,
    type: 'mixed',
    items: [for (final item in hub.page.items) item.toMediaItem()],
    size: hub.page.totalResults ?? hub.page.items.length,
    // Discover answers a shelf in one shot and ignores container offsets, so
    // there is no second page to promise — View All shows what came back.
    more: false,
  );

  bool _handleVerticalNavigation(int index, bool isUp) => navigateVerticalHubRows(
    hubCount: _hubs.length,
    hubIndex: index,
    isUp: isUp,
    requestFocus: (target) => _rowKeys[_hubs[target].id]?.currentState?.requestFocusFromMemory(),
  );

  void _openViewAll(MediaHub hub) {
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HubDetailScreen(hub: hub))));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _error != null || _hubs.isEmpty) {
      return Scaffold(
        body: CustomScrollView(
          slivers: [
            CustomAppBar(title: Text(widget.title), pinned: true),
            if (_loading)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (_error case final message?)
              SliverErrorState(message: message, onRetry: _load)
            else
              SliverFillRemaining(child: Center(child: Text(t.hubDetail.noItemsFound))),
          ],
        ),
      );
    }

    // The same widgets the home screen uses on each form factor, so the cards
    // are the size and spacing the viewer already knows.
    return PlatformDetector.isTV() ? _buildTvRail() : _buildSections();
  }

  Widget _buildTvRail() => Scaffold(
    body: TvSpotlightScaffold(
      hubs: _hubs,
      spotlightListenable: _spotlight,
      resolveSpotlight: () => _spotlight.resolve(_hubs),
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
              hubs: _hubs,
              focusMemory: _focusMemory,
              iconForHub: (hub, _) => hubIconFor(hub),
              onFocusedItemChanged: _spotlight.select,
              trailingForHub: (_) => TvRailTrailing.viewAll,
              onViewAll: _openViewAll,
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

  Widget _buildSections() => Scaffold(
    body: CustomScrollView(
      slivers: [
        CustomAppBar(title: Text(widget.title), pinned: true),
        for (var index = 0; index < _hubs.length; index++)
          SliverToBoxAdapter(
            child: HubSection(
              key: _rowKeys.putIfAbsent(_hubs[index].id, GlobalKey<HubSectionState>.new),
              hub: _hubs[index],
              focusMemory: _focusMemory,
              icon: hubIconFor(_hubs[index]),
              onVerticalNavigation: (isUp) => _handleVerticalNavigation(index, isUp),
              onViewAll: () => _openViewAll(_hubs[index]),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    ),
  );
}
