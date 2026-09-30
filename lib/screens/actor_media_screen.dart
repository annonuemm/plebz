import 'dart:async';

import 'package:flutter/material.dart';
import '../focus/focusable_action_bar.dart';
import '../focus/focusable_wrapper.dart';
import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/library_query.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../mixins/grid_focus_node_mixin.dart';
import '../mixins/paginated_item_loader.dart';
import '../mixins/standard_paginated_view.dart';
import '../models/catalog/catalog_item.dart';
import '../providers/catalog_sources_provider.dart';
import '../services/settings_service.dart';
import '../services/tmdb/tmdb_client.dart';
import '../services/tmdb/tmdb_fill_in_service.dart';
import '../theme/mono_tokens.dart';
import '../utils/app_logger.dart';
import '../utils/error_message_utils.dart';
import '../utils/external_ids.dart';
import '../utils/media_image_helper.dart';
import '../utils/media_server_http_client.dart';
import '../utils/provider_extensions.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/loading_indicator_box.dart';
import '../widgets/optimized_media_image.dart';
import 'base_media_list_detail_screen.dart';
import 'catalog_item_detail_screen.dart';
import 'focusable_detail_screen_mixin.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

/// Screen to browse all media featuring a specific actor.
class ActorMediaScreen extends StatefulWidget {
  final String actorName;
  final String personId;
  final String? actorThumb;
  final String? characterName;

  /// The title the viewer reached this person from. It is what names the
  /// person at TMDB — see [TmdbFillInService.filmographyFor] — so without it
  /// the filmography stays off.
  final MediaItem? sourceTitle;
  final String serverId;
  final String? serverName;
  final MediaBackend backend;

  const ActorMediaScreen({
    super.key,
    required this.actorName,
    required this.personId,
    this.actorThumb,
    this.characterName,
    this.sourceTitle,
    required this.serverId,
    this.serverName,
    required this.backend,
  });

  @override
  State<ActorMediaScreen> createState() => _ActorMediaScreenState();
}

class _ActorMediaScreenState extends BaseMediaListDetailScreen<ActorMediaScreen>
    with
        GridFocusNodeMixin<ActorMediaScreen>,
        FocusableDetailScreenMixin<ActorMediaScreen>,
        PaginatedItemLoader<MediaItem, ActorMediaScreen>,
        PaginatedItemUpdatable<ActorMediaScreen>,
        StandardPaginatedView<MediaItem, ActorMediaScreen> {
  static const int _pageSize = 200;

  @override
  MediaItem get mediaItem => MediaItem(
    id: '',
    backend: widget.backend,
    kind: MediaKind.unknown,
    serverId: widget.serverId,
    serverName: widget.serverName,
  );

  @override
  String get title => widget.actorName;

  @override
  String get emptyMessage => t.discover.noContentAvailable;

  @override
  bool get hasItems => totalSize > 0;

  @override
  void dispose() {
    disposePagination();
    disposeFocusResources();
    super.dispose();
  }

  MediaServerClient get _mediaClient => context.getMediaClientForServer(ServerId(widget.serverId));

  /// The server may be offline (a cast tap from an offline detail): the header
  /// then shows the fallback avatar and the load reports the failure, instead
  /// of the lookup throwing during build.
  MediaServerClient? get _mediaClientOrNull => context.tryGetMediaClientForServer(ServerId(widget.serverId));

  /// Credits TMDB knows about that none of the loaded titles matches.
  List<TmdbCredit> _missingCredits = const [];

  /// One lookup at a time: the Discover match can take a moment, and a second
  /// press while it runs would open two pages.
  bool _openingCredit = false;

  bool _loadingFilmography = false;

  /// Loads the filmography once the library titles are in, because it is the
  /// library titles that decide which credits are missing.
  bool get _filmographyEnabled =>
      widget.sourceTitle != null &&
      (TmdbFillInService.instanceOrNull?.isEnabled ?? false) &&
      SettingsService.instance.read(SettingsService.showActorFilmography);

  Future<void> _loadFilmography() async {
    final source = widget.sourceTitle;
    final service = TmdbFillInService.instanceOrNull;
    if (!_filmographyEnabled || source == null || service == null) return;

    if (mounted) setState(() => _loadingFilmography = true);
    final credits = await service.filmographyFor(
      sourceTitle: source,
      personName: widget.actorName,
      client: _mediaClient,
    );
    if (!mounted) return;
    setState(() => _loadingFilmography = false);
    if (credits.isEmpty) return;

    final owned = {for (final item in loadedItems.values) _matchKey(item.displayTitle, item.year)};
    final missing = [
      for (final credit in credits)
        if (!owned.contains(_matchKey(credit.title, credit.year))) credit,
    ];
    setState(() => _missingCredits = missing);
  }

  /// Titles are matched by name and year because that is all both sides carry
  /// here: a library listing has no external ids, and fetching them per title
  /// would be one request per row. Asking TMDB in the app's language is what
  /// makes the names line up. A year is allowed to be one out, since release
  /// and library years disagree across new-year boundaries.
  static String _matchKey(String title, int? year) {
    final normalized = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '$normalized|${year ?? 0}';
  }

  /// Opens a credit the viewer does not own.
  ///
  /// TMDB knows the title, Plex Discover has the page: the id is resolved into
  /// a Discover entry and the ordinary catalog detail screen takes it from
  /// there — the same page Explore opens, so nothing new has to be invented
  /// and "in these libraries" still answers whether it is available after all.
  Future<void> _openCredit(TmdbCredit credit) async {
    if (_openingCredit) return;
    final sources = context.read<CatalogSourcesProvider>();
    final plex = sources.connectedSources.where((source) => source.id == CatalogSourceId.plex).firstOrNull;
    if (plex == null) {
      showErrorSnackBar(context, t.actor.noDiscoverSource);
      return;
    }

    setState(() => _openingCredit = true);
    final kind = credit.isMovie ? MediaKind.movie : MediaKind.show;
    CatalogItemIds? ids;
    try {
      ids = await plex.resolveItemIds(kind, ExternalIds(tmdb: credit.tmdbId), title: credit.title);
    } catch (error, stackTrace) {
      appLogger.d('Discover lookup failed for ${credit.title}', error: error, stackTrace: stackTrace);
    }
    if (!mounted) return;
    setState(() => _openingCredit = false);

    if (ids == null) {
      // Discover's id match misses titles its own search finds, and the search
      // fallback verifies by id; when both come up empty there is no page to
      // open, and saying so beats a screen that loads nothing.
      showErrorSnackBar(context, t.actor.notOnDiscover(title: credit.title));
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CatalogItemDetailScreen(
          item: CatalogItem(
            source: CatalogSourceId.plex,
            kind: kind,
            title: credit.title,
            year: credit.year,
            ids: ids!,
            posterUrl: credit.posterUrl,
          ),
        ),
      ),
    );
  }

  Widget _missingCreditTile(TmdbCredit credit) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(flatRadius(context, 8)),
            child: OptimizedMediaImage(
              client: null,
              imagePath: credit.posterUrl,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              imageType: ImageType.poster,
              fallbackIcon: credit.isMovie ? Symbols.movie_rounded : Symbols.tv_rounded,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(credit.title, maxLines: 1, overflow: .ellipsis, style: theme.textTheme.bodySmall),
        if (credit.year != null)
          Text('${credit.year}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  /// The loading and empty states, which the base screen decides from the
  /// library list alone.
  ///
  /// A person can be absent from every library here and still have a
  /// filmography worth showing, and fetching it takes a moment — so "no
  /// content" must not be announced over it, nor before it has arrived.
  List<Widget> _stateSlivers() {
    if (_missingCredits.isNotEmpty) return const [];
    // Only when there is nothing on screen yet; a spinner above a full grid
    // would read as the grid being wrong.
    if (_loadingFilmography && !hasItems) return [LoadingIndicatorBox.sliver];
    return buildStateSlivers();
  }

  List<Widget> _buildMissingSection() {
    if (_missingCredits.isEmpty) return const [];
    final theme = Theme.of(context);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(t.actor.notInLibraries, style: theme.textTheme.titleMedium?.copyWith(fontWeight: .bold)),
        ),
      ),
      // One dimming for the whole block rather than per card: it is the
      // section that is unavailable, not each poster individually.
      SliverOpacity(
        opacity: 0.45,
        sliver: SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              childAspectRatio: 0.52,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => FocusableWrapper(
                onSelect: () => unawaited(_openCredit(_missingCredits[index])),
                child: _missingCreditTile(_missingCredits[index]),
              ),
              childCount: _missingCredits.length,
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPage(int start, int size, AbortController? abort) {
    return _mediaClient.fetchPersonMediaPage(widget.personId, start: start, size: size, abort: abort);
  }

  @override
  Future<void> loadItems() {
    return loadStandardPaginatedItems(
      pageSize: _pageSize,
      errorMessageFor: (error, stackTrace) => localizedLoadErrorMessage(error, stackTrace, context: widget.actorName),
      onLoaded: (loadedCount, totalCount) {
        appLogger.d('Loaded $loadedCount of $totalCount items for actor: ${widget.actorName}');
        autoFocusFirstItemAfterLoad();
        unawaited(_loadFilmography());
      },
    );
  }

  @override
  List<FocusableAction> getAppBarActions() {
    return [];
  }

  Widget _buildActorHeader() {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(flatRadius(context, 40)),
              child: OptimizedMediaImage(
                client: _mediaClientOrNull,
                imagePath: widget.actorThumb,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                imageType: ImageType.avatar,
                fallbackIcon: Symbols.person_rounded,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    widget.actorName,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: .bold),
                    maxLines: 2,
                    overflow: .ellipsis,
                  ),
                  if (widget.characterName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.characterName!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                  ],
                  if (totalSize > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      t.discover.titleCount(n: totalSize),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return buildDetailScaffold(
      slivers: [
        CustomAppBar(title: Text(widget.actorName), pinned: true, actions: buildFocusableAppBarActions()),
        _buildActorHeader(),
        ..._stateSlivers(),
        if (hasItems)
          buildSparseFocusableGrid(
            totalItems: totalSize,
            itemAt: (index) => loadedItems[index],
            onRefresh: updateItem,
            onSkeletonVisible: (index) => ensureIndexLoaded(index, pageSize: _pageSize),
          ),
        ..._buildMissingSection(),
      ],
    );
  }
}
