import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../focus/dpad_navigator.dart';
import '../focus/focusable_action_bar.dart';
import '../focus/focusable_button.dart';
import '../focus/focusable_wrapper.dart';
import '../focus/input_mode_tracker.dart';
import '../focus/key_event_utils.dart';
import '../focus/locked_hub_controller.dart';
import '../i18n/app_locale_utils.dart';
import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/library_copy_quality.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_item_merge.dart';
import '../media/media_kind.dart';
import '../media/media_rating.dart';
import '../models/catalog/catalog_cast_member.dart';
import '../models/catalog/catalog_item.dart';
import '../models/catalog/catalog_labels.dart';
import '../models/catalog/catalog_metadata.dart';
import '../providers/catalog_sources_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/seerr_account_provider.dart';
import '../services/catalog/catalog_library_matcher.dart';
import '../services/catalog/catalog_source.dart';
import '../services/catalog/library_copy_quality_loader.dart';
import '../services/catalog/seerr_catalog_source.dart';
import '../services/data_aggregation_service.dart';
import '../services/settings_service.dart';
import '../theme/mono_tokens.dart';
import '../utils/app_logger.dart';
import '../utils/catalog_navigation_helper.dart';
import '../utils/country_codes.dart';
import '../utils/desktop_window_padding.dart';
import '../utils/formatters.dart';
import '../utils/language_codes.dart';
import '../utils/media_image_helper.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/platform_detector.dart';
import '../utils/rating_utils.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/app_bar_back_button.dart';
import '../widgets/detail_home_button.dart';
import '../widgets/app_icon.dart';
import '../widgets/cast_member_strip.dart';
import '../widgets/collapsible_text.dart';
import '../widgets/corner_backdrop.dart';
import '../widgets/focusable_tab_chip.dart';
import '../widgets/hub_section.dart';
import '../redesign/ocker_skin.dart';
import '../widgets/library_copy_jump_button.dart';
import '../widgets/library_copy_tile.dart';
import '../widgets/optimized_media_image.dart';
import '../widgets/overlay_sheet.dart';
import '../widgets/seerr_request_sheet.dart';
import '../widgets/settings_builder.dart';
import '../widgets/settings_section.dart';
import '../widgets/stat_chip.dart';

/// Detail screen for a catalog item (Explore tab). Renders from provider
/// data — no media server required — and resolves library availability in
/// place: an "In these libraries" list when the item is owned, tappable
/// through to the normal media detail screen.
class CatalogItemDetailScreen extends StatefulWidget {
  final CatalogItem item;

  /// For tests; the app opens a library copy's detail page.
  final void Function(MediaItem copy)? onOpenLibraryCopy;

  const CatalogItemDetailScreen({super.key, required this.item, this.onOpenLibraryCopy});

  @override
  State<CatalogItemDetailScreen> createState() => _CatalogItemDetailScreenState();
}

class _CatalogItemDetailScreenState extends State<CatalogItemDetailScreen> {
  final _actionBarKey = GlobalKey<FocusableActionBarState>();
  final _backButtonFocusNode = FocusNode(debugLabel: 'catalog_detail_back');
  final _homeButtonFocusNode = FocusNode(debugLabel: 'catalog_detail_home');
  final _castSectionKey = GlobalKey();
  final _castStripKey = GlobalKey<CastMemberStripState>();
  final _relatedSectionKey = GlobalKey<HubSectionState>();
  final _hubFocusMemory = HubFocusMemory();
  final ScrollController _scrollController = ScrollController();
  final _spoilerTagFocusNode = FocusNode(debugLabel: 'catalog_spoiler_tags');
  final _overviewFocusNode = FocusNode(debugLabel: 'catalog_overview');
  final _backgroundFocusNode = FocusNode(debugLabel: 'catalog_background');
  List<FocusNode> _linkFocusNodes = const [];
  List<FocusNode> _relationFocusNodes = const [];
  List<CatalogTag> _orderedTags = const [];
  List<CatalogLink> _streamingLinks = const [];
  bool _showSpoilerTags = false;

  /// Focus node per library copy, keyed by [MediaItem.globalKey] so a later
  /// resolution pass that adds a copy keeps the nodes — and therefore the
  /// focus — of the rows already on screen. [_libraryMatchFocusNodes] is the
  /// same nodes in display order, for index-based dpad traversal.
  final Map<String, FocusNode> _libraryMatchNodesByKey = {};
  List<FocusNode> _libraryMatchFocusNodes = const [];
  CatalogSource? _watchlistSource;
  bool _mutatingWatchlist = false;

  CatalogItem? _detailItem;

  /// Library items matching this catalog item; null while resolving.
  List<MediaItem>? _matches;

  /// Coverage belongs to the newest launched (detail-enriched) query, not the
  /// union of historical successes. Verified copies are merged independently.
  int _resolutionGeneration = 0;
  bool _resolvingMatches = false;
  final Set<String> _uncheckedServerIds = {};

  /// What each copy's server said about its file, by [MediaItem.globalKey];
  /// null where it could not say. Asked only once there are two copies to
  /// tell apart, and it decides their order: see [_compareCopies].
  final Map<String, LibraryCopyQuality?> _copyQuality = {};
  LibraryCopyQualityLoader? _qualityLoader;
  int _qualityGeneration = 0;
  bool _comparingCopies = false;

  /// Whether the cursor has been moved onto the best-copy button once. It is
  /// moved there only the first time the button can be pressed, and only
  /// from where the page put it.
  bool _bestCopyFocusSettled = false;

  /// Cast/characters from the item's own source; null while loading (the
  /// section only renders once loaded non-empty).
  List<CatalogCastMember>? _cast;

  /// "More like this" from the item's own source; null while loading (the
  /// row only renders once loaded non-empty).
  List<CatalogItem>? _related;

  /// Labelled franchise edges, flattened to one entry per title. Providers
  /// routinely return a single sequel or spin-off per label, and a shelf per
  /// label spent a whole hub row — header, scroll row, one card — on it.
  List<({CatalogRelationType type, CatalogItem item})> _relationEntries = const [];

  @override
  void initState() {
    super.initState();
    _syncDetailCollections(widget.item);
    unawaited(_resolveMatches(widget.item));
    unawaited(_loadDetail());
    final sources = context.read<CatalogSourcesProvider>();
    _watchlistSource = sources.watchlistSourceFor(widget.item);
    final source = _watchlistSource;
    if (source != null) {
      source.watchlistChanges.addListener(_onWatchlistChanged);
      if (source.isOnWatchlist(widget.item.kind, widget.item.ids) == null) {
        unawaited(source.ensureWatchlistLoaded());
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _actionBarKey.currentState?.requestFocusOnFirst();
    });
  }

  @override
  void dispose() {
    _backButtonFocusNode.dispose();
    _homeButtonFocusNode.dispose();
    _spoilerTagFocusNode.dispose();
    _overviewFocusNode.dispose();
    _backgroundFocusNode.dispose();
    for (final node in _linkFocusNodes) {
      node.dispose();
    }
    _watchlistSource?.watchlistChanges.removeListener(_onWatchlistChanged);
    for (final node in _libraryMatchNodesByKey.values) {
      node.dispose();
    }
    for (final node in _relationFocusNodes) {
      node.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onWatchlistChanged() {
    // ignore: no-empty-block - membership state lives in the source
    setState(() {});
  }

  Future<void> _resolveMatches(CatalogItem item) async {
    final generation = ++_resolutionGeneration;
    _resolvingMatches = true;
    LibraryLookupResult result;
    try {
      result = await context.read<CatalogLibraryMatcher>().match(item);
    } catch (e) {
      appLogger.w('Catalog library match failed for ${item.identityKey}', error: e);
      if (!mounted) return;
      if (generation == _resolutionGeneration) {
        _resolvingMatches = false;
        _uncheckedServerIds
          ..clear()
          ..addAll(context.read<MultiServerProvider>().expectedServerIds);
      }
      _mergeMatches(const []);
      return;
    }
    if (!mounted) return;
    if (generation == _resolutionGeneration) {
      _resolvingMatches = false;
      _uncheckedServerIds
        ..clear()
        ..addAll(result.failedServerIds)
        ..addAll(result.cancelledServerIds)
        ..addAll(result.unqueriedServerIds);
    }
    _mergeMatches(result.items);
  }

  /// Fold a resolution pass into the visible copies.
  ///
  /// Union, never replace. The bare row item and its detail-enriched form
  /// resolve concurrently, and `findByExternalIdsAcrossServers` logs and skips
  /// per-server failures — so a later pass can legitimately come back short a
  /// server that answered the first one. Replacing would drop rows for copies
  /// that are still there.
  void _mergeMatches(List<MediaItem> matches) {
    if (!mounted) return;
    final focused = _libraryMatchNodesByKey.values.firstWhereOrNull((node) => node.hasPrimaryFocus);
    final merged = mergeLibraryCopies(_matches ?? const [], matches)..sort(_compareCopies);
    final keys = {for (final match in merged) match.globalKey};
    for (final key in _libraryMatchNodesByKey.keys.toList()) {
      if (!keys.contains(key)) _libraryMatchNodesByKey.remove(key)!.dispose();
    }
    _libraryMatchFocusNodes = [
      for (final match in merged)
        _libraryMatchNodesByKey.putIfAbsent(
          match.globalKey,
          () => FocusNode(
            debugLabel: 'catalog_library_match_${match.globalKey}',
            // Resolved live: merging a pass can reorder the rows, so a
            // captured index would steer the wrong copy.
            onKeyEvent: (node, event) {
              final index = _libraryMatchFocusNodes.indexOf(node);
              return index < 0 ? KeyEventResult.ignored : _handleLibraryMatchKey(index, event);
            },
          ),
        ),
    ];
    setState(() => _matches = merged);
    // A merge re-sorts, and SettingsGroup shapes its cards by list index, so
    // the tile holding the focused node can be rebuilt from scratch and drop
    // it. Reclaim it rather than dumping a dpad user on another copy.
    if (focused != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || focused.hasPrimaryFocus || focused.context == null) return;
        focused.requestFocus();
      });
    }
    _measureCopies(merged);
    _settleBestCopyFocus();
  }

  /// Best copy first: what the servers said about the files, then — where
  /// they said nothing, or the same — the lookup's own order.
  int _compareCopies(MediaItem a, MediaItem b) {
    final byQuality = compareLibraryCopyQuality(_copyQuality[a.globalKey], _copyQuality[b.globalKey]);
    return byQuality != 0 ? byQuality : compareLibraryCopies(a, b);
  }

  /// Ask each copy's server what it holds, once there are two to compare. A
  /// single copy is the best by default and costs nothing.
  void _measureCopies(List<MediaItem> copies) {
    if (copies.length < 2) return;
    final unmeasured = [
      for (final copy in copies)
        if (!_copyQuality.containsKey(copy.globalKey)) copy,
    ];
    if (unmeasured.isEmpty) return;
    final generation = ++_qualityGeneration;
    final multiServer = context.read<MultiServerProvider>();
    final loader = _qualityLoader ??= LibraryCopyQualityLoader(
      clientFor: (copy) {
        final serverId = serverIdOrNull(copy.serverId);
        return serverId == null ? null : multiServer.getClientForServer(serverId);
      },
      dolbyVisionDisabled: SettingsService.instanceOrNull?.read(SettingsService.disableDolbyVision) ?? false,
    );
    setState(() => _comparingCopies = true);
    unawaited(
      Future.wait([for (final copy in unmeasured) loader.load(copy)]).then((results) {
        if (!mounted) return;
        for (var i = 0; i < unmeasured.length; i++) {
          _copyQuality[unmeasured[i].globalKey] = results[i];
        }
        if (generation == _qualityGeneration) _comparingCopies = false;
        // Re-sort what is on screen with what the servers said.
        _mergeMatches(const []);
      }),
    );
  }

  /// The copy the button opens, once it is known to be the best.
  MediaItem? get _bestCopy {
    final matches = _matches;
    if (matches == null || matches.isEmpty || _comparingCopies) return null;
    return matches.first;
  }

  void _openBestCopy() {
    final copy = _bestCopy;
    if (copy != null) _openCopy(copy);
  }

  /// A copy's detail page on its own server — the button's way and a row's.
  void _openCopy(MediaItem copy) {
    final open = widget.onOpenLibraryCopy;
    if (open != null) {
      open(copy);
    } else {
      unawaited(navigateToMediaItemDetails(context, copy));
    }
  }

  /// The first time the button can be pressed, the cursor moves onto it — if
  /// it is still where the page put it, on the first of the other buttons,
  /// and the page has not been scrolled. Anywhere else it stays.
  void _settleBestCopyFocus() {
    if (_bestCopyFocusSettled || _bestCopy == null) return;
    _bestCopyFocusSettled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients && _scrollController.offset > 0) return;
      final focused = FocusManager.instance.primaryFocus?.debugLabel;
      final startedOn = _watchlistSource != null
          ? 'catalog_watchlist'
          : _canRequest
          ? 'catalog_request'
          : 'catalog_trailer';
      if (focused != null && focused != startedOn) return;
      _actionBarKey.currentState?.requestFocusOnFirst();
    });
  }

  /// Under the button, what the viewer should know about the copy it opens:
  /// that it lacks episodes another copy has, and which servers were not
  /// asked at all.
  String? get _bestCopyNote {
    final best = _bestCopy;
    if (best == null) return null;
    final notes = <String>[];
    final have = _copyQuality[best.globalKey]?.episodes;
    final most = _copyQuality.values.map((quality) => quality?.episodes ?? 0).fold<int>(0, (a, b) => a > b ? a : b);
    if (have != null && have < most) notes.add(t.explore.episodesOf(have: have, total: most));
    if (_uncheckedServerIds.isNotEmpty) {
      final manager = context.read<MultiServerProvider>().serverManager;
      final names = [for (final id in _uncheckedServerIds) manager.serverDisplayName(ServerId(id))];
      notes.add(t.explore.notChecked(servers: names.join(', ')));
    }
    return notes.isEmpty ? null : notes.join(' · ');
  }

  CatalogSource? get _ownSource =>
      context.read<CatalogSourcesProvider>().connectedSources.firstWhereOrNull((s) => s.id == widget.item.source);

  CatalogItem get _item => _detailItem ?? widget.item;

  /// Whether this title can be requested, which depends on an id the opening
  /// row may not have yet. Re-run once the detail body has been fetched.
  void _syncDetailCollections(CatalogItem item) {
    final tags = [
      for (final tag in item.tags ?? const <CatalogTag>[])
        if (tag.name.trim().isNotEmpty) tag,
    ]..sort((a, b) => (b.rank ?? -1).compareTo(a.rank ?? -1));
    // Only streaming links are shown. The provider's own page ("Open on
    // Simkl") is where the user already came from, so the section it filled
    // was a link back to the source of the page they are reading.
    final streamingLinks = <CatalogLink>[];
    for (final link in item.links ?? const <CatalogLink>[]) {
      if (link.label.trim().isEmpty || link.url.trim().isEmpty) continue;
      if (!link.isStreaming) continue;
      streamingLinks.add(link);
    }
    for (final node in _linkFocusNodes) {
      node.dispose();
    }
    _orderedTags = tags;
    _streamingLinks = streamingLinks;
    // One node per rendered link: D-pad traversal walks this list by index, so
    // a node without a widget behind it would strand the focus.
    _linkFocusNodes = [
      for (var index = 0; index < streamingLinks.length; index++) FocusNode(debugLabel: 'catalog_external_link_$index'),
    ];
  }

  /// One lazy detail load against the item's own source; failures keep the
  /// opening item visible and leave provider-only sections hidden.
  Future<void> _loadDetail() async {
    final source = _ownSource;
    if (source == null) return;
    try {
      final detail = await source.fetchDetail(widget.item);
      if (!mounted) return;
      final relationEntries = [
        for (final relation in detail.relations)
          for (final item in relation.items) (type: relation.type, item: item),
      ];
      _syncDetailCollections(detail.item);
      _replaceRelationFocusNodes(relationEntries.length);
      setState(() {
        _detailItem = detail.item;
        _cast = detail.cast;
        _related = detail.related;
        _relationEntries = relationEntries;
      });
      // The row form of a Plex Discover item carries only its rating key;
      // the detail body brings the external ids (#1715). Ask again with the
      // full set whenever enrichment added id forms — not just when the bare
      // lookup came back empty: the exact `plex://` guid finds only copies in
      // libraries on the modern agent, while a legacy-agent sibling is
      // reachable solely through the imdb/tmdb forms (#1754). Likewise when
      // it added title candidates (Trakt aliases and translations, #2098): a
      // copy filed under a romaji or localized title is reachable only
      // through that title. The result merges, so a re-ask can only add
      // copies.
      final gainedIds = !widget.item.ids.allKeys.toSet().containsAll(detail.item.ids.allKeys);
      final gainedTitles = !CatalogLibraryMatcher.lookupTitles(
        widget.item,
      ).toSet().containsAll(CatalogLibraryMatcher.lookupTitles(detail.item));
      if (gainedIds || gainedTitles) {
        unawaited(_resolveMatches(detail.item));
      }
    } catch (e) {
      appLogger.d('Catalog detail load failed for ${widget.item.identityKey}', error: e);
    }
  }

  void _replaceRelationFocusNodes(int count) {
    for (final node in _relationFocusNodes) {
      node.dispose();
    }
    _relationFocusNodes = [
      for (var index = 0; index < count; index++) FocusNode(debugLabel: 'catalog_relation_$index'),
    ];
  }

  bool get _hasTrailer => _item.trailerUrl?.trim().isNotEmpty ?? false;

  /// The Seerr source when the signed-in user may request this kind. Read
  /// live rather than captured in initState: the account provider adopts
  /// permission changes in place (bind-time refresh, silent re-auth, a
  /// denied request's `/auth/me` probe) without rebuilding the client, and a
  /// disconnect swaps the source for null — a captured source would outlive
  /// its disposed client. `build` subscribes to both so the action bar
  /// tracks grants and revocations.
  SeerrCatalogSource? get _requestSource {
    final seerr = context.read<CatalogSourcesProvider>().seerrSource;
    return seerr != null && seerr.canRequest(widget.item.kind) ? seerr : null;
  }

  /// Whether a copy of this film is in one of the user's own libraries.
  ///
  /// First-hand evidence, and it can disagree with the provider: Seerr knows
  /// a library only through its own scan, which lines titles up by TMDB id —
  /// a film Plex matched to a different id, or one added since the last scan,
  /// is missing from that index while sitting in the library all the same.
  ///
  /// Films only. A series in the library may still be missing seasons, which
  /// is exactly what a request is for.
  bool get _isInLibrary => _item.kind == MediaKind.movie && (_matches?.isNotEmpty ?? false);

  /// Whether asking for this title would ask for anything.
  ///
  /// A title already on the server has nothing to request. A partly available
  /// series keeps the action: the seasons that are missing are exactly what a
  /// request is for. So does a title the provider says nothing about — most
  /// providers do not know your server, and silence is not availability.
  bool get _isOnServer => _isInLibrary || _item.serverState?.availability == CatalogAvailability.available;

  /// The fill of a refused request. The same red the active tab chip wears,
  /// so "this one is different" reads the same way across the app.
  static const Color _declinedChipColor = activeTabChipColor;

  /// How long a title has to have been out before asking for it is useful.
  /// Nothing reaches a server the day it is released.
  static const Duration _requestableAfterRelease = Duration(days: 7);

  /// Whether the title is still too new to ask for: not out yet, or out for
  /// less than [_requestableAfterRelease].
  ///
  /// A title with no known date stays requestable — plenty of entries simply
  /// carry no date, and refusing on missing data would hide the action for
  /// them too.
  bool get _tooNewToRequest {
    final released = _item.releaseDate;
    if (released == null) return false;
    return DateTime.now().difference(released) < _requestableAfterRelease;
  }

  /// Whether the Request action can actually render: the tmdb id may only
  /// arrive with the detail fetch (see [_loadDetail]), so read the enriched
  /// item. Trakt items carry one natively and MAL items get theirs from the
  /// Fribb mapping at row time, but Plex Discover's hub/search/related
  /// endpoints ignore includeGuids, so a Plex item's tmdb id only arrives
  /// with the detail fetch (issue #1959).
  bool get _canRequest => _requestSource != null && _item.ids.tmdb != null && !_isOnServer && !_tooNewToRequest;

  bool get _hasActions => _watchlistSource != null || _canRequest || _hasTrailer || (_matches?.isNotEmpty ?? false);

  bool get _hasLibraryMatches => _libraryMatchFocusNodes.isNotEmpty;

  bool get _hasSpoilerTags => _orderedTags.any((tag) => tag.isSpoiler);

  bool get _hasSpoilerReveal => _hasSpoilerTags && !_showSpoilerTags;

  bool get _hasDetailActions => _hasSpoilerReveal || _linkFocusNodes.isNotEmpty;

  bool get _hasOverview => _item.overview?.trim().isNotEmpty ?? false;

  bool get _hasBackground => _item.background?.trim().isNotEmpty ?? false;

  /// Prose sections rendered as dpad stops (overview, MAL background prose).
  bool get _hasTextStops => _hasOverview || _hasBackground;

  bool get _hasCast => _cast?.isNotEmpty ?? false;

  bool get _hasRelations => _relationEntries.isNotEmpty;

  bool get _hasRelated => _related?.isNotEmpty ?? false;

  bool get _hasSectionsBelowCast => _hasRelations || _hasRelated;

  void _revealFocusNode(FocusNode? node, {double alignment = 0.3}) {
    final focusContext = node?.context;
    if (focusContext == null) return;
    unawaited(
      Scrollable.ensureVisible(
        focusContext,
        alignment: alignment,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
  }

  void _requestLibraryMatchFocus(int index) {
    if (index < 0 || index >= _libraryMatchFocusNodes.length) return;
    final node = _libraryMatchFocusNodes[index];
    node.requestFocus();
    _revealFocusNode(node);
  }

  void _requestLinkFocus(int index) {
    if (index < 0 || index >= _linkFocusNodes.length) return;
    final node = _linkFocusNodes[index];
    node.requestFocus();
    _revealFocusNode(node);
  }

  /// Prose stops are top-aligned: an expanded overview should read from its
  /// first line, not start 30% down with its opening already scrolled past.
  void _requestOverviewFocus() {
    _overviewFocusNode.requestFocus();
    _revealFocusNode(_overviewFocusNode, alignment: 0.1);
  }

  void _requestBackgroundFocus() {
    _backgroundFocusNode.requestFocus();
    _revealFocusNode(_backgroundFocusNode, alignment: 0.1);
  }

  void _requestFirstDetailActionFocus() {
    if (_hasSpoilerReveal) {
      _spoilerTagFocusNode.requestFocus();
      _revealFocusNode(_spoilerTagFocusNode);
    } else {
      _requestLinkFocus(0);
    }
  }

  void _requestLastDetailActionFocus() {
    if (_linkFocusNodes.isNotEmpty) {
      _requestLinkFocus(_linkFocusNodes.length - 1);
    } else if (_hasSpoilerReveal) {
      _spoilerTagFocusNode.requestFocus();
      _revealFocusNode(_spoilerTagFocusNode);
    }
  }

  void _requestCastFocus() {
    if (!(_cast?.isNotEmpty ?? false)) return;
    _castStripKey.currentState?.requestFocus();
    final sectionContext = _castSectionKey.currentContext;
    if (sectionContext == null) return;
    unawaited(
      Scrollable.ensureVisible(
        sectionContext,
        alignment: 0.3,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
  }

  void _requestActionBarFocus() {
    _actionBarKey.currentState?.requestFocusOnFirst();
    if (!_scrollController.hasClients) return;
    unawaited(_scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut));
  }

  void _requestRelationFocus(int index) {
    if (index < 0 || index >= _relationFocusNodes.length) return;
    final node = _relationFocusNodes[index];
    node.requestFocus();
    _revealFocusNode(node);
  }

  void _requestRelatedFocus() {
    _relatedSectionKey.currentState?.requestFocusFromMemory();
  }

  void _focusSectionBelowCast() {
    if (_hasRelations) {
      _requestRelationFocus(0);
    } else {
      _requestRelatedFocus();
    }
  }

  bool _focusSectionBelowLibraryMatches() {
    if (_hasCast) {
      _requestCastFocus();
      return true;
    }
    if (_hasSectionsBelowCast) {
      _focusSectionBelowCast();
      return true;
    }
    return false;
  }

  void _focusSectionBelowDetailActions() {
    if (_hasLibraryMatches) {
      _requestLibraryMatchFocus(0);
    } else if (_hasCast) {
      _requestCastFocus();
    } else if (_hasSectionsBelowCast) {
      _focusSectionBelowCast();
    }
  }

  /// UP from the action row on a television: the home button in the corner,
  /// with the page brought back to its top so the button is in view.
  void _focusHomeButton() {
    _homeButtonFocusNode.requestFocus();
    if (_scrollController.hasClients) {
      unawaited(_scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut));
    }
  }

  void _focusSectionBelowActions() {
    if (_hasOverview) {
      _requestOverviewFocus();
    } else {
      _focusSectionBelowOverview();
    }
  }

  void _focusSectionBelowOverview() {
    if (_hasBackground) {
      _requestBackgroundFocus();
    } else {
      _focusSectionBelowTextStops();
    }
  }

  void _focusSectionBelowTextStops() {
    if (_hasDetailActions) {
      _requestFirstDetailActionFocus();
    } else {
      _focusSectionBelowDetailActions();
    }
  }

  void _focusSectionAboveBackground() {
    if (_hasOverview) {
      _requestOverviewFocus();
    } else {
      _requestActionBarFocus();
    }
  }

  void _focusSectionAboveDetailActions() {
    if (_hasBackground) {
      _requestBackgroundFocus();
    } else {
      _focusSectionAboveBackground();
    }
  }

  void _focusSectionAboveLibraryMatches() {
    if (_hasDetailActions) {
      _requestLastDetailActionFocus();
    } else {
      _focusSectionAboveDetailActions();
    }
  }

  void _focusSectionAboveCast() {
    if (_hasLibraryMatches) {
      _requestLibraryMatchFocus(_libraryMatchFocusNodes.length - 1);
    } else if (_hasDetailActions) {
      _requestLastDetailActionFocus();
    } else {
      _focusSectionAboveDetailActions();
    }
  }

  void _focusSectionAboveRelations() {
    if (_hasCast) {
      _requestCastFocus();
    } else {
      _focusSectionAboveCast();
    }
  }

  void _focusSectionAboveRelated() {
    if (_hasRelations) {
      _requestRelationFocus(_relationEntries.length - 1);
    } else {
      _focusSectionAboveRelations();
    }
  }

  KeyEventResult _handleLibraryMatchKey(int index, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key.isUpKey) {
      if (index > 0) {
        _requestLibraryMatchFocus(index - 1);
      } else if (_hasDetailActions || _hasTextStops || _hasActions) {
        _focusSectionAboveLibraryMatches();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      if (index + 1 < _libraryMatchFocusNodes.length) {
        _requestLibraryMatchFocus(index + 1);
      } else if (!_focusSectionBelowLibraryMatches()) {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _revealSpoilerTags() {
    if (!_hasSpoilerReveal) return;
    setState(() => _showSpoilerTags = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_linkFocusNodes.isNotEmpty) {
        _requestLinkFocus(0);
      } else {
        _focusSectionBelowDetailActions();
      }
    });
  }

  Future<void> _openExternalUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      appLogger.d('Catalog external URL is invalid: $value');
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) appLogger.d('Catalog external URL could not be opened: $value');
    } catch (e) {
      appLogger.d('Catalog external URL failed to open: $value', error: e);
    }
  }

  bool? get _isOnWatchlist => _watchlistSource?.isOnWatchlist(_item.kind, _item.ids);

  Future<void> _toggleWatchlist() async {
    final source = _watchlistSource;
    if (source == null || _mutatingWatchlist) return;
    _mutatingWatchlist = true;
    try {
      var current = _isOnWatchlist;
      if (current == null) {
        // Membership is not known yet — the snapshot is loaded once per
        // session and this page may be the first thing to want it. Waiting
        // for it is what the press meant; dropping the press left the button
        // doing nothing at all, with nothing said about why.
        await source.ensureWatchlistLoaded();
        if (!mounted) return;
        current = _isOnWatchlist;
      }
      // Still unknown: the provider could not be read — Plex Discover answers
      // 504 often enough for this to be ordinary. That is a failed *read*,
      // and it must not block a *write*: adding needs the item's own id, not
      // the list. The button shows "add" while membership is unknown, so
      // adding is what the press meant.
      current ??= false;

      if (current) {
        await source.removeFromWatchlist(_item.kind, _item.ids, title: _item.title);
      } else {
        await source.addToWatchlist(_item.kind, _item.ids, title: _item.title);
      }
    } catch (e, stackTrace) {
      // Logged as well as shown: the usual cause is a title the watchlist's
      // own provider cannot resolve from the ids this page has, and the
      // message alone does not say which.
      appLogger.w('Watchlist toggle failed for ${_item.identityKey}', error: e, stackTrace: stackTrace);
      if (mounted) showErrorSnackBar(context, t.explore.watchlistUpdateFailed);
    } finally {
      _mutatingWatchlist = false;
    }
  }

  /// The artwork above the header.
  ///
  /// Follows the same "backdrop in the corner" setting the TV spotlight does:
  /// this page is reached straight from Explore, and a page that changes its
  /// artwork treatment on the way in reads as a different app. Off, the
  /// artwork is a full-width strip; on, it sits in the top-right corner with
  /// its edges feathered away.
  ///
  /// The strip is why the setting is worth honouring here: 320 logical pixels
  /// across the full width is an aspect ratio of about 6:1, and covering that
  /// with a 16:9 photograph magnifies it several times over.
  Widget _buildBackdrop(BuildContext context, String backdropUrl) {
    return SettingValueBuilder<bool>(
      pref: SettingsService.tvCornerSpotlightBackdrop,
      builder: (context, corner, _) {
        if (!corner) {
          return Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: ShaderMask(
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black.withValues(alpha: 0.0)],
                stops: const [0.3, 1.0],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: OptimizedMediaImage.thumb(
                imagePath: backdropUrl,
                width: double.infinity,
                height: 320,
                fit: BoxFit.cover,
                fallbackIcon: null,
              ),
            ),
          );
        }

        final size = cornerBackdropSize(MediaQuery.sizeOf(context));
        return Positioned(
          top: 0,
          right: 0,
          child: CornerBackdrop(
            width: size.width,
            height: size.height,
            child: OptimizedMediaImage.thumb(
              imagePath: backdropUrl,
              width: size.width,
              height: size.height,
              fit: BoxFit.cover,
              fallbackIcon: null,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLibraryMatchTile(MediaItem match, int index) => LibraryCopyTile(
    copy: match,
    focusNode: _libraryMatchFocusNodes[index],
    quality: _copyQuality[match.globalKey],
    onTap: () => _openCopy(match),
  );

  /// Library availability, resolved in place: a progress row while the
  /// matcher runs, "Not in your library" when every server answered and none
  /// matched, "Couldn't check n servers" when nothing matched but a server
  /// never answered, otherwise an "In these libraries" list whose rows open
  /// the normal media detail screen — with the unchecked count beneath it
  /// when a server sat the lookup out. Rows are focusable tiles (dpad-safe,
  /// background focus effect).
  Widget _buildLibrarySection(ThemeData theme) {
    final mutedColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(color: mutedColor);
    final matches = _matches;

    if (matches == null || (matches.isEmpty && _resolvingMatches)) {
      return Row(
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          // Flexible: on a phone held upright the line ran past the edge.
          Flexible(child: Text(t.explore.checkingLibrary, style: mutedStyle)),
        ],
      );
    }

    final unchecked = _uncheckedServerIds.length;
    Widget note(String text, {required IconData icon}) => Row(
      children: [
        AppIcon(icon, fill: 1, size: 18, color: mutedColor),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: mutedStyle)),
      ],
    );

    if (matches.isEmpty) {
      return unchecked == 0
          ? note(t.explore.notInLibrary, icon: Symbols.info_rounded)
          : note(t.explore.libraryCheckFailed(n: unchecked), icon: Symbols.cloud_off_rounded);
    }

    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(t.explore.inTheseLibraries, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        // M3E grouped cards, same row anatomy as the settings/trackers hub:
        // server-type logo leading, name, chevron trailing.
        SettingsGroup(
          margin: EdgeInsets.zero,
          children: [
            for (var index = 0; index < matches.length; index++) _buildLibraryMatchTile(matches[index], index),
          ],
        ),
        if (unchecked > 0) ...[
          const SizedBox(height: 8),
          note(t.explore.libraryCheckFailed(n: unchecked), icon: Symbols.cloud_off_rounded),
        ],
      ],
    );
  }

  String get _metaLine {
    final item = _item;
    final parts = <String>[
      if (_releaseLabel case final released?) released else if (item.year != null) '${item.year}',
      if (item.runtimeMinutes != null) formatDurationTextual(Duration(minutes: item.runtimeMinutes!).inMilliseconds),
      if (item.certification?.trim().isNotEmpty ?? false) item.certification!.trim(),
    ];
    return parts.join(' • ');
  }

  /// The full release date, for a title recent enough that the day matters —
  /// null for everything older, where the bare year reads better.
  ///
  /// A year on its own says nothing about whether a title is already out, and
  /// for anything from this year that is the question being asked. Titles from
  /// last December keep the date a little longer for the same reason.
  String? get _releaseLabel {
    final released = _item.releaseDate;
    if (released == null) return null;
    final now = DateTime.now();
    final recent = released.year >= now.year || now.difference(released) < const Duration(days: 30);
    if (!recent) return null;
    return DateFormat.yMMMd(LocaleSettings.currentLocale.intlLocaleName).format(released.toLocal());
  }

  static String? _joinValues(Iterable<String>? raw, {String Function(String value)? displayName}) {
    if (raw == null) return null;
    final values = <String>[];
    final seen = <String>{};
    for (final rawValue in raw) {
      final value = rawValue.trim();
      if (value.isEmpty) continue;
      final displayed = displayName?.call(value) ?? value;
      if (displayed.trim().isNotEmpty && seen.add(displayed)) values.add(displayed);
    }
    return values.isEmpty ? null : values.join(' • ');
  }

  /// Headline score, leaderboard context, audience counts, availability and
  /// release-shape facts that fit the established compact chip treatment.
  /// The mean of every attributed score, when the user asked for one and there
  /// is more than one score to combine. Null otherwise — a lone score is not an
  /// average of anything, so it keeps its own attributed chip below.
  double? _combinedRating() {
    if (!SettingsService.instance.read(SettingsService.averageRatings)) return null;
    final ratings = _item.ratings ?? const <MediaRatingSource>[];
    if (ratings.length < 2) return null;
    return averagedRatings(ratings).single.value;
  }

  Widget? _buildStatsChips() {
    final item = _item;
    final locale = LocaleSettings.currentLocale.intlLocaleName;
    final compact = NumberFormat.compact(locale: locale);
    final chips = <Widget>[];
    void add(String? label, {IconData? icon, Color? iconColor, Color? backgroundColor, Color? labelColor}) {
      if (label?.trim().isNotEmpty ?? false) {
        chips.add(
          StatChip(
            icon: icon,
            iconColor: iconColor,
            label: label!,
            backgroundColor: backgroundColor,
            labelColor: labelColor,
          ),
        );
      }
    }

    // With averaging on, the combined score takes the headline chip's place and
    // the Ratings section below is dropped, so the page carries exactly one
    // number instead of a headline score, a section, and an average of it.
    if (_combinedRating() case final combined?) {
      add(
        '${t.common.ratingSource.average} ${combined.toStringAsFixed(1)}',
        icon: Symbols.star_rounded,
        iconColor: Colors.amber,
      );
    } else if (item.rating case final rating?) {
      var score = rating.toStringAsFixed(1);
      if (item.votes case final votes?) {
        score = '$score (${t.explore.stats.votes(n: compact.format(votes))})';
      }
      add(score, icon: Symbols.star_rounded, iconColor: Colors.amber);
    }
    if (item.airStatus case final status?) add(statusLabel(status));
    if (item.episodeCount case final count?) add(t.explore.episodeCount(n: count));
    if (item.unairedEpisodeCount case final count?) add(t.explore.detail.unairedEpisodes(n: count));
    add(item.network);
    if (item.broadcastSeason case final season?) add(seasonLabel(season));
    if (item.format case final format?) add(formatLabel(format));
    if (item.sourceMaterial case final source?) add(sourceMaterialLabel(source));
    if (item.isAdult == true) add(t.explore.badge.adult);
    if (item.addedAt case final addedAt?) {
      add(t.explore.detail.addedOn(date: DateFormat.yMMMd(locale).format(addedAt.toLocal())));
    }
    for (final rank in item.ranks ?? const <CatalogRank>[]) {
      add(rankLabel(rank));
    }

    final audience = item.audience;
    if (audience != null) {
      if (audience.watchingNow case final count?) add(t.explore.badge.watchingNow(n: compact.format(count)));
      if (audience.listed case final count?) add(t.explore.stats.listed(n: compact.format(count)));
      if (audience.viewers case final count? when audience.viewersPeriod != null) {
        final formatted = compact.format(count);
        add(switch (audience.viewersPeriod!) {
          CatalogAudiencePeriod.day => t.explore.stats.viewersDay(n: formatted),
          CatalogAudiencePeriod.week => t.explore.stats.viewersWeek(n: formatted),
          CatalogAudiencePeriod.month => t.explore.stats.viewersMonth(n: formatted),
          CatalogAudiencePeriod.year => t.explore.stats.viewersYear(n: formatted),
          CatalogAudiencePeriod.allTime => t.explore.stats.viewersAllTime(n: formatted),
        });
      }
      if (audience.planning case final count?) add(t.explore.stats.planning(n: compact.format(count)));
      if (audience.watching case final count?) add(t.explore.stats.watching(n: compact.format(count)));
      if (audience.completed case final count?) add(t.explore.stats.completed(n: compact.format(count)));
      if (audience.onHold case final count?) add(t.explore.stats.onHold(n: compact.format(count)));
      if (audience.dropped case final count?) add(t.explore.stats.dropped(n: compact.format(count)));
      if (audience.favorited case final count?) add(t.explore.stats.favorited(n: compact.format(count)));
      if (audience.dropRate case final rate?) {
        add(t.explore.stats.dropRate(percent: NumberFormat.percentPattern(locale).format(rate)));
      }
      if (audience.comments case final count?) add(t.explore.stats.comments(n: count));
    }

    // The provider carries no word for "not here": absence of the available
    // badge is the only thing that says so, which leaves a copy the provider
    // missed looking like a copy that does not exist. What the app found
    // first-hand says it outright.
    if (_isInLibrary && item.serverState?.availability != CatalogAvailability.available) {
      add(availabilityLabel(CatalogAvailability.available, is4k: false), icon: Symbols.check_circle_rounded);
    }

    final server = item.serverState;
    if (server != null) {
      if (server.availability case final availability?) {
        add(availabilityLabel(availability, is4k: false));
      }
      if (server.availability4k case final availability?) {
        add(availabilityLabel(availability, is4k: true));
      }
      // A refusal is the one state worth finding without reading: it is why
      // the title is not coming, and it reads as just another fact in the
      // quiet fill every other chip wears.
      if (server.request case final request?) {
        final declined = request == CatalogRequestState.declined;
        add(
          requestStateLabel(request, is4k: false),
          backgroundColor: declined ? _declinedChipColor : null,
          labelColor: declined ? Colors.white : null,
        );
      }
      if (server.request4k case final request?) {
        final declined = request == CatalogRequestState.declined;
        add(
          requestStateLabel(request, is4k: true),
          backgroundColor: declined ? _declinedChipColor : null,
          labelColor: declined ? Colors.white : null,
        );
      }
      if (server.availableSeasons case final available? when server.totalSeasons != null) {
        add(t.explore.badge.seasonsAvailable(available: available, total: server.totalSeasons!));
      }
    }

    if (chips.isEmpty) return null;
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  /// Attributed scores, each behind its own brand badge where the source has
  /// one — the same Rotten Tomatoes/IMDb/TMDB marks the media detail screen
  /// draws. Sources without a mark (`critic`, `audience`, tracker scores)
  /// keep their written label.
  Widget? _buildRatingsSection(ThemeData theme) {
    final compact = NumberFormat.compact(locale: LocaleSettings.currentLocale.intlLocaleName);
    // The combined score is shown in the stats chips under the poster, so the
    // section would only repeat it under a heading.
    if (_combinedRating() != null) return null;
    final chips = <Widget>[];
    for (final rating in _item.ratings ?? const <MediaRatingSource>[]) {
      final source = ratingSourceLabel(rating.source);
      final badge = ratingInfoForSource(rating.source, rating.value);
      if (source == null && badge == null) continue;
      var label = badge == null ? '$source ${rating.value.toStringAsFixed(1)}' : badge.formattedValue;
      if (rating.votes case final votes?) {
        label = '$label (${t.explore.stats.votes(n: compact.format(votes))})';
      }
      chips.add(
        badge == null
            ? StatChip(icon: Symbols.star_rounded, iconColor: Colors.amber, label: label)
            : StatChip(
                leading: SvgPicture.asset(badge.assetPath, width: 14, height: 14, semanticsLabel: source),
                label: label,
              ),
      );
    }
    if (chips.isEmpty) return null;
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(t.explore.detail.ratings, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
      ],
    );
  }

  Widget? _buildScheduleSection(ThemeData theme) {
    final item = _item;
    final chips = <Widget>[];
    final locale = LocaleSettings.currentLocale.intlLocaleName;
    final broadcast = item.broadcast;
    if (broadcast?.weekday case final weekday? when weekday >= DateTime.monday && weekday <= DateTime.sunday) {
      final time = broadcast!.time?.trim();
      if (time?.isNotEmpty ?? false) {
        final day = DateFormat.EEEE(locale).format(DateTime.utc(2024, 1, weekday));
        final timezone = broadcast.timezone?.trim();
        chips.add(
          StatChip(
            label: timezone?.isNotEmpty ?? false
                ? t.explore.broadcastWithZone(day: day, time: time!, timezone: timezone!)
                : t.explore.broadcast(day: day, time: time!),
          ),
        );
      }
    }
    if (item.nextEpisode case final next?) {
      final duration = formatDurationTextual(next.timeUntil(DateTime.now()).inMilliseconds);
      chips.add(
        StatChip(
          label: next.episode == null
              ? t.explore.badge.nextAiringIn(duration: duration)
              : t.explore.badge.nextEpisodeIn(episode: next.episode!, duration: duration),
        ),
      );
    }
    if (chips.isEmpty) return null;
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(t.explore.detail.schedule, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
      ],
    );
  }

  Widget _buildFactRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.65)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  /// Gap between definition-grid columns, and between relation tiles.
  static const double _factColumnSpacing = 24;
  static const double _relationTileSpacing = 12;

  /// Definition rows flow into columns once there is room for them: budget,
  /// box office and the rest are short values, and one pair per line leaves
  /// most of a desktop window empty.
  Widget _buildFactGrid(ThemeData theme, List<({String label, String value})> facts) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _gridColumns(constraints.maxWidth, facts.length);
        if (columns < 2) {
          return Column(
            crossAxisAlignment: .start,
            children: [for (final fact in facts) _buildFactRow(theme, fact.label, fact.value)],
          );
        }
        final columnWidth = (constraints.maxWidth - _factColumnSpacing * (columns - 1)) / columns;
        return Wrap(
          spacing: _factColumnSpacing,
          children: [
            for (final fact in facts) SizedBox(width: columnWidth, child: _buildFactRow(theme, fact.label, fact.value)),
          ],
        );
      },
    );
  }

  /// Columns that fit [width], never more than there are entries: two facts
  /// on a wide window stay two columns instead of stretching to three.
  static int _gridColumns(double width, int count) {
    final fits = width >= 1100
        ? 3
        : width >= 700
        ? 2
        : 1;
    return fits < count ? fits : count;
  }

  Widget? _buildFactsSection(ThemeData theme) {
    final item = _item;
    final locale = LocaleSettings.currentLocale.intlLocaleName;
    final dateFormat = DateFormat.yMMMd(locale);
    final currency = NumberFormat.simpleCurrency(locale: locale, name: 'USD', decimalDigits: 0);
    final facts = <({String label, String value})>[];
    void add(String label, String? value) {
      if (value?.trim().isNotEmpty ?? false) facts.add((label: label, value: value!));
    }

    add(t.explore.detail.originalTitle, item.originalTitle);
    add(t.explore.detail.alsoKnownAs, _joinValues(item.altTitles));
    add(t.explore.detail.studios, _joinValues(item.studios));
    add(t.explore.detail.country, _joinValues(item.countries, displayName: CountryCodes.getDisplayName));
    add(t.explore.detail.language, _joinValues(item.languages, displayName: LanguageCodes.getDisplayName));
    if (item.releaseDate case final date?) add(t.explore.detail.released, dateFormat.format(date.toLocal()));
    if (item.physicalReleaseDate case final date?) {
      add(t.explore.detail.physicalRelease, dateFormat.format(date.toLocal()));
    }
    if (item.endDate case final date?) add(t.explore.detail.ended, dateFormat.format(date.toLocal()));
    if (item.userRating case final rating?) add(t.explore.detail.yourRating, rating.toStringAsFixed(1));
    if (item.budget case final budget?) add(t.explore.detail.budget, currency.format(budget));
    if (item.revenue case final revenue?) add(t.explore.detail.revenue, currency.format(revenue));
    add(t.explore.detail.contentAdvisory, item.contentAdvisory);
    if (facts.isEmpty) return null;
    return _buildFactGrid(theme, facts);
  }

  Widget? _buildRecommendersSection(ThemeData theme) {
    final recommenders = _item.recommenders;
    if (recommenders == null || recommenders.isEmpty) return null;
    return Column(
      crossAxisAlignment: .start,
      children: [
        for (var index = 0; index < recommenders.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          Text(switch (recommenders[index].reason) {
            CatalogRecommendationReason.favorited => t.explore.detail.favoritedBy(who: recommenders[index].displayName),
            CatalogRecommendationReason.recommended => t.explore.detail.recommendedBy(
              who: recommenders[index].displayName,
            ),
          }, style: theme.textTheme.titleSmall),
          if (recommenders[index].note?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 4),
            Text(recommenders[index].note!.trim(), style: theme.textTheme.bodyMedium),
          ],
        ],
      ],
    );
  }

  Widget? _buildCrewSection(ThemeData theme) {
    final credits = _item.credits;
    if (credits == null || credits.isEmpty) return null;
    final rows = <({String label, String value})>[];
    for (final role in CatalogCreditRole.values) {
      final names = _joinValues(credits.where((credit) => credit.role == role).map((credit) => credit.name));
      if (names != null) rows.add((label: creditRoleLabel(role), value: names));
    }
    if (rows.isEmpty) return null;
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(t.explore.detail.crew, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _buildFactGrid(theme, rows),
      ],
    );
  }

  Widget? _buildTagsSection(ThemeData theme) {
    if (_orderedTags.isEmpty) return null;
    final visibleTags = [
      for (final tag in _orderedTags)
        if (!tag.isSpoiler || _showSpoilerTags) tag,
    ];
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(t.explore.detail.tags, style: theme.textTheme.titleMedium),
        if (visibleTags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final tag in visibleTags) StatChip(label: tag.name)]),
        ],
        if (_hasSpoilerReveal) ...[
          const SizedBox(height: 8),
          FocusableButton(
            focusNode: _spoilerTagFocusNode,
            onPressed: _revealSpoilerTags,
            onNavigateUp: _hasActions || _hasTextStops ? _focusSectionAboveDetailActions : null,
            onNavigateDown: _linkFocusNodes.isNotEmpty ? () => _requestLinkFocus(0) : _focusSectionBelowDetailActions,
            child: OutlinedButton.icon(
              onPressed: _revealSpoilerTags,
              icon: const AppIcon(Symbols.visibility_rounded, fill: 1),
              label: Text(t.explore.detail.revealSpoilerTags),
            ),
          ),
        ],
      ],
    );
  }

  void _focusAboveLinkGroup(int startIndex) {
    if (startIndex > 0) {
      _requestLinkFocus(startIndex - 1);
    } else if (_hasSpoilerReveal) {
      _spoilerTagFocusNode.requestFocus();
      _revealFocusNode(_spoilerTagFocusNode);
    } else {
      _focusSectionAboveDetailActions();
    }
  }

  void _focusBelowLinkGroup(int endIndex) {
    if (endIndex < _linkFocusNodes.length) {
      _requestLinkFocus(endIndex);
    } else {
      _focusSectionBelowDetailActions();
    }
  }

  Widget _buildLinksSection(ThemeData theme, String title, List<CatalogLink> links, int startIndex) {
    final endIndex = startIndex + links.length;
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var localIndex = 0; localIndex < links.length; localIndex++)
              FocusableButton(
                focusNode: _linkFocusNodes[startIndex + localIndex],
                onPressed: () => unawaited(_openExternalUrl(links[localIndex].url)),
                onNavigateLeft: localIndex > 0 ? () => _requestLinkFocus(startIndex + localIndex - 1) : null,
                onNavigateRight: localIndex + 1 < links.length
                    ? () => _requestLinkFocus(startIndex + localIndex + 1)
                    : null,
                onNavigateUp: () => _focusAboveLinkGroup(startIndex),
                onNavigateDown: () => _focusBelowLinkGroup(endIndex),
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_openExternalUrl(links[localIndex].url)),
                  icon: const AppIcon(Symbols.open_in_new_rounded, fill: 1),
                  label: Text(t.explore.detail.openOn(site: links[localIndex].label)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildBackgroundSection(ThemeData theme, String background, {required bool isMobile}) {
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(t.explore.detail.background, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        CollapsibleText(
          text: background,
          maxLines: isMobile ? 6 : 4,
          style: theme.textTheme.bodyLarge,
          focusNode: _backgroundFocusNode,
          skipTraversal: false,
          onNavigateUp: _hasOverview || _hasActions ? _focusSectionAboveBackground : null,
          onNavigateDown: _focusSectionBelowTextStops,
        ),
      ],
    );
  }

  /// Horizontal cast strip — the same [CastMemberStrip] cards as the media
  /// detail screen. Trakt serves actors with their character; MAL serves
  /// characters with their role, so the section is titled accordingly.
  Widget _buildCastSection(ThemeData theme, List<CatalogCastMember> cast) {
    return Column(
      key: _castSectionKey,
      crossAxisAlignment: .start,
      children: [
        Text(
          const {CatalogSourceId.mal, CatalogSourceId.anilist}.contains(_item.source)
              ? t.explore.characters
              : t.explore.cast,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        CastMemberStrip(
          key: _castStripKey,
          members: [
            for (final member in cast) (name: member.name, secondary: member.secondary, imagePath: member.imageUrl),
          ],
          onNavigateUp: _hasLibraryMatches || _hasDetailActions || _hasTextStops || _hasActions
              ? _focusSectionAboveCast
              : null,
          onNavigateDown: _hasSectionsBelowCast ? _focusSectionBelowCast : null,
          debugLabel: 'catalog_cast_row',
        ),
      ],
    );
  }

  /// Labelled franchise edges as compact rows rather than one hub per label:
  /// a provider that returns a single sequel used to spend an entire shelf on
  /// it. Rows flow into columns on wide viewports, like the facts above.
  Widget _buildRelationsSection(ThemeData theme) {
    final posterTargetPx = MediaImageHelper.artworkTargetPx(context, 40);
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = _relationEntries.length;
        final columns = _gridColumns(constraints.maxWidth, count);
        final tileWidth = (constraints.maxWidth - _relationTileSpacing * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: .start,
          children: [
            Text(t.explore.detail.relatedTitles, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: _relationTileSpacing,
              runSpacing: _relationTileSpacing,
              children: [
                for (var index = 0; index < count; index++)
                  SizedBox(
                    width: tileWidth,
                    child: _buildRelationTile(
                      theme,
                      index,
                      columns: columns,
                      count: count,
                      posterTargetPx: posterTargetPx,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildRelationTile(
    ThemeData theme,
    int index, {
    required int columns,
    required int count,
    required int posterTargetPx,
  }) {
    final entry = _relationEntries[index];
    final item = entry.item;
    final label = relationLabel(entry.type);
    final year = item.year;
    void open() => unawaited(navigateToCatalogItem(context, item));
    return FocusableWrapper(
      focusNode: _relationFocusNodes[index],
      borderRadius: 12,
      semanticLabel: '$label: ${item.title}',
      onSelect: open,
      onNavigateUp: index >= columns ? () => _requestRelationFocus(index - columns) : _focusSectionAboveRelations,
      onNavigateDown: index + columns < count
          ? () => _requestRelationFocus(index + columns)
          : _hasRelated
          ? _requestRelatedFocus
          : null,
      onNavigateLeft: index % columns == 0 ? null : () => _requestRelationFocus(index - 1),
      onNavigateRight: (index + 1) % columns == 0 || index + 1 >= count ? null : () => _requestRelationFocus(index + 1),
      child: GestureDetector(
        onTap: open,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: tokens(context).tileFill,
            borderRadius: BorderRadius.circular(flatRadius(context, 12)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(flatRadius(context, 6)),
                child: OptimizedMediaImage.poster(imagePath: item.posterFor(posterTargetPx), width: 40, height: 60),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  mainAxisSize: .min,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      year == null ? item.title : '${item.title} • $year',
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: .ellipsis,
                    ),
                  ],
                ),
              ),
              AppIcon(
                Symbols.chevron_right_rounded,
                fill: 1,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Taste-based recommendations stay separate from labelled franchise facts.
  Widget _buildRelatedSection(List<CatalogItem> related) {
    return HubSection(
      key: _relatedSectionKey,
      hub: MediaHub(
        id: 'catalog-related:${_item.source.name}:${_item.identityKey}',
        identifier: 'explore.related',
        title: t.discover.moreLikeThis,
        type: 'mixed',
        items: [for (final item in related) item.toMediaItem()],
        size: related.length,
      ),
      focusMemory: _hubFocusMemory,
      icon: Symbols.recommend_rounded,
      inset: true,
      onNavigateUp: _focusSectionAboveRelated,
      cardSizing: HubCardSizing.grid,
    );
  }

  void _handleSystemBack() {
    if (BackKeyCoordinator.consumeIfHandled()) return;
    Navigator.pop(context);
  }

  /// The actions and the note under them. [width] is the room the row has
  /// when it stands on its own line (a narrow screen): the best copy's button
  /// then gives up what the other buttons need, its name shortened rather
  /// than cut off at the edge.
  List<Widget> _actionsSection(
    BuildContext hostContext, {
    required bool? onWatchlist,
    required int? tmdbId,
    required double? width,
  }) {
    final item = _item;
    final theme = Theme.of(context);
    final others = [
      _watchlistSource != null,
      _requestSource is SeerrCatalogSource && tmdbId != null && !_isOnServer && !_tooNewToRequest,
      item.trailerUrl?.trim().isNotEmpty ?? false,
    ].where((shown) => shown).length;
    final copyMaxWidth = width == null ? null : math.max(140.0, width - others * 56 - 2 * ockerBandMargin(context) - 8);
    Widget bounded(Widget button) => copyMaxWidth == null
        ? button
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: copyMaxWidth),
            child: button,
          );
    return [
      const SizedBox(height: 16),
      if (_hasActions)
        // Under glass one band, as the
        // header's destinations are, and
        // focus its capsule gliding along.
        OckerGlassBand(
          overhang: EdgeInsets.all(ockerBandMargin(context)),
          child: FocusableActionBar(
            key: _actionBarKey,
            wrapBuiltAction: ockerGlass(context)
                ? (context, state, child) =>
                      OckerWordFocus(focused: state.showFocus, outset: EdgeInsets.zero, child: child)
                : null,
            onNavigateDown: _focusSectionBelowActions,
            onNavigateUp: PlatformDetector.isTV() ? _focusHomeButton : null,
            actions: [
              // The title on the viewer's own server, in its
              // best copy — first, because when there is one
              // it is what the page is most often opened for.
              if (_matches?.isNotEmpty ?? false)
                FocusableAction(
                  debugLabel: 'catalog_best_copy',
                  onPressed: _bestCopy == null ? null : _openBestCopy,
                  builder: (context, state) => bounded(
                    LibraryCopyJumpButton(
                      copy: _bestCopy,
                      quality: _bestCopy == null ? null : _copyQuality[_bestCopy!.globalKey],
                      showFocus: state.showFocus,
                      onPressed: _bestCopy == null ? null : _openBestCopy,
                    ),
                  ),
                ),
              if (_watchlistSource != null)
                FocusableAction(
                  // Stable identities so the focused binding survives the
                  // list-shape changes of async enrichment (watchlist/request
                  // sources and trailer URL arrive at different times).
                  debugLabel: 'catalog_watchlist',
                  icon: onWatchlist ?? false ? Symbols.bookmark_added_rounded : Symbols.bookmark_add_rounded,
                  tooltip: onWatchlist ?? false ? t.explore.removeFromWatchlist : t.explore.addToWatchlist,
                  onPressed: () => unawaited(_toggleWatchlist()),
                ),
              if (_requestSource case final SeerrCatalogSource seerr
                  when tmdbId != null && !_isOnServer && !_tooNewToRequest)
                FocusableAction(
                  debugLabel: 'catalog_request',
                  // Not the download arrow: that
                  // is the app's own downloading,
                  // and the two were mistaken for
                  // each other.
                  icon: Symbols.add_to_queue_rounded,
                  tooltip: t.seerr.request,
                  onPressed: () => unawaited(
                    showSeerrRequestSheet(
                      hostContext,
                      source: seerr,
                      kind: item.kind,
                      tmdbId: tmdbId,
                      releaseDate: item.releaseDate,
                      title: item.title,
                    ),
                  ),
                ),
              if (item.trailerUrl?.trim() case final trailer? when trailer.isNotEmpty)
                FocusableAction(
                  debugLabel: 'catalog_trailer',
                  icon: Symbols.play_circle_rounded,
                  tooltip: t.explore.detail.watchTrailer,
                  onPressed: () => unawaited(_openExternalUrl(trailer)),
                ),
            ],
          ),
        ),
      if (_bestCopyNote case final note?) ...[
        const SizedBox(height: 8),
        Text(
          note,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final theme = Theme.of(context);
    final onWatchlist = _isOnWatchlist;
    final tmdbId = item.ids.tmdb;
    // Subscriptions for [_requestSource]: the source itself (disconnect) and
    // the permission mask (grant/revoke), both adopted in place upstream.
    context.select<CatalogSourcesProvider, SeerrCatalogSource?>((sources) => sources.seerrSource);
    context.select<SeerrAccountProvider?, int?>((account) => account?.permissions);
    // The backdrop strip spans the full screen width (Positioned left/right: 0
    // below), and backdropFor is width-keyed: target the rendered width, not
    // the 320px slot height.
    final backdropUrl = item.backdropFor(
      MediaImageHelper.artworkTargetPx(context, MediaQuery.sizeOf(context).width, imageType: ImageType.art),
    );
    final posterUrl = item.posterFor(MediaImageHelper.artworkTargetPx(context, 140));
    final isMobile = PlatformDetector.isMobile(context);
    // A phone held upright: too little room beside the poster for the actions.
    final narrow = !PlatformDetector.isTV() && MediaQuery.sizeOf(context).width < 600;

    final viewInsets = MediaQuery.paddingOf(context);
    final blockSystemBack = PlatformDetector.isTV() || InputModeTracker.shouldBlockSystemBack(context);
    // Match the established detail-screen back policy: TV/keyboard back is
    // owned by the focus tree, while native mobile back and iOS swipe-back
    // remain route-driven. The overlay host always gets first refusal.
    return OverlaySheetHost(
      canPop: !blockSystemBack,
      onSystemBack: _handleSystemBack,
      child: Builder(
        builder: (hostContext) => Focus(
          onKeyEvent: (_, event) => handleBackKeyNavigation(hostContext, event),
          child: Scaffold(
            body: Stack(
              children: [
                SingleChildScrollView(
                  key: const Key('catalog_detail_scroll'),
                  controller: _scrollController,
                  // The backdrop lives inside the scrollable so it moves with
                  // the content (it extends under the status bar, so the safe
                  // areas are baked into the content padding instead of a
                  // SafeArea around the scroll view).
                  child: Stack(
                    children: [
                      if (backdropUrl != null) _buildBackdrop(context, backdropUrl),
                      // Horizontal-only SafeArea: the backdrop above stays
                      // full-bleed; only the foreground content clears the
                      // landscape notch. Vertical insets are baked into the
                      // padding (see above).
                      SafeArea(
                        top: false,
                        bottom: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(24, viewInsets.top + 120, 24, viewInsets.bottom + 32),
                          child: Column(
                            crossAxisAlignment: .start,
                            children: [
                              Row(
                                crossAxisAlignment: .start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(flatRadius(context, 12)),
                                    child: OptimizedMediaImage.poster(imagePath: posterUrl, width: 140, height: 210),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: .start,
                                      children: [
                                        if (item.tagline?.trim() case final tagline? when tagline.isNotEmpty) ...[
                                          Text(
                                            tagline,
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                        ],
                                        Text(
                                          item.title,
                                          style: theme.textTheme.headlineMedium,
                                          maxLines: 3,
                                          overflow: .ellipsis,
                                        ),
                                        if (_metaLine.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            _metaLine,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                            ),
                                          ),
                                        ],
                                        if (item.genres?.isNotEmpty ?? false) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            item.genres!.join(' • '),
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                            ),
                                          ),
                                        ],
                                        if (!narrow)
                                          ..._actionsSection(
                                            hostContext,
                                            onWatchlist: onWatchlist,
                                            tmdbId: tmdbId,
                                            width: null,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              // On a narrow screen — a phone held upright — the
                              // actions take the full width under the poster:
                              // beside it the best copy's button ran off the
                              // edge and took the watchlist button with it.
                              if (narrow)
                                LayoutBuilder(
                                  builder: (context, constraints) => Column(
                                    crossAxisAlignment: .start,
                                    children: _actionsSection(
                                      hostContext,
                                      onWatchlist: onWatchlist,
                                      tmdbId: tmdbId,
                                      width: constraints.maxWidth,
                                    ),
                                  ),
                                ),
                              SettingValueBuilder<bool>(
                                pref: SettingsService.averageRatings,
                                builder: (context, _, _) {
                                  final chips = _buildStatsChips();
                                  if (chips == null) return const SizedBox.shrink();
                                  return Padding(padding: const EdgeInsets.only(top: 20), child: chips);
                                },
                              ),
                              if (item.overview?.trim() case final overview? when overview.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                CollapsibleText(
                                  text: overview,
                                  maxLines: isMobile ? 6 : 4,
                                  style: theme.textTheme.bodyLarge,
                                  focusNode: _overviewFocusNode,
                                  skipTraversal: false,
                                  onNavigateUp: _hasActions ? _requestActionBarFocus : null,
                                  onNavigateDown: _focusSectionBelowOverview,
                                ),
                              ],
                              if (item.background?.trim() case final background? when background.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                _buildBackgroundSection(theme, background, isMobile: isMobile),
                              ],
                              // Gated as one unit — spacing included — so hiding
                              // the grid leaves no orphaned gap behind it.
                              SettingValueBuilder<bool>(
                                pref: SettingsService.showCatalogDetailFacts,
                                builder: (context, showFacts, _) {
                                  if (!showFacts) return const SizedBox.shrink();
                                  final facts = _buildFactsSection(theme);
                                  if (facts == null) return const SizedBox.shrink();
                                  return Padding(padding: const EdgeInsets.only(top: 24), child: facts);
                                },
                              ),
                              if (_buildRecommendersSection(theme) case final Widget recommenders) ...[
                                const SizedBox(height: 24),
                                recommenders,
                              ],
                              SettingValueBuilder<bool>(
                                pref: SettingsService.averageRatings,
                                builder: (context, _, _) {
                                  final ratings = _buildRatingsSection(theme);
                                  if (ratings == null) return const SizedBox.shrink();
                                  return Padding(padding: const EdgeInsets.only(top: 24), child: ratings);
                                },
                              ),
                              if (_buildScheduleSection(theme) case final Widget schedule) ...[
                                const SizedBox(height: 24),
                                schedule,
                              ],
                              // Gated as one unit — spacing included — so
                              // hiding it leaves no orphaned gap behind.
                              SettingValueBuilder<bool>(
                                pref: SettingsService.showCatalogDetailCrew,
                                builder: (context, showCrew, _) {
                                  if (!showCrew) return const SizedBox.shrink();
                                  final crew = _buildCrewSection(theme);
                                  if (crew == null) return const SizedBox.shrink();
                                  return Padding(padding: const EdgeInsets.only(top: 24), child: crew);
                                },
                              ),
                              if (_buildTagsSection(theme) case final Widget tags) ...[
                                const SizedBox(height: 24),
                                tags,
                              ],
                              if (_streamingLinks.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                _buildLinksSection(theme, t.explore.detail.watchOn, _streamingLinks, 0),
                              ],
                              const SizedBox(height: 24),
                              _buildLibrarySection(theme),
                              if (_cast case final List<CatalogCastMember> cast when cast.isNotEmpty) ...[
                                const SizedBox(height: 28),
                                _buildCastSection(theme, cast),
                              ],
                              if (_hasRelations) ...[const SizedBox(height: 24), _buildRelationsSection(theme)],
                              if (_related case final List<CatalogItem> related when related.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                _buildRelatedSection(related),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Not on a television: there the remote's own back key is
                // what leaves a page, and an arrow nobody can click is a
                // target the D-pad has to be walked around. The home button
                // is there on both, beside the arrow or alone in its corner:
                // the remote has no key that leaves a run of pages at once.
                if (!PlatformDetector.isTV())
                  Positioned(
                    top: 0,
                    left: 0,
                    child: DesktopAppBarHelper.buildAdjustedLeading(
                      Row(
                        mainAxisSize: .min,
                        children: [
                          AppBarBackButton(style: BackButtonStyle.circular, focusNode: _backButtonFocusNode),
                          const DetailHomeBesideBack(),
                        ],
                      ),
                      context: hostContext,
                    )!,
                  )
                else
                  Positioned(
                    top: viewInsets.top + 20,
                    left: 24,
                    child: DetailHomeButton(
                      focusNode: _homeButtonFocusNode,
                      onNavigateDown: () => _actionBarKey.currentState?.requestFocusOnFirst(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
