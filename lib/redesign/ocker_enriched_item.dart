import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../media/catalog_item_ref.dart';
import '../media/media_item.dart';
import '../utils/app_logger.dart';
import '../media/media_role.dart';
import '../models/catalog/catalog_cast_member.dart';
import '../models/catalog/catalog_item.dart';
import '../models/catalog/catalog_metadata.dart';
import '../providers/catalog_sources_provider.dart';

/// Fills a thin catalog row out from its own provider before drawing it.
///
/// A row from Explore carries a poster and a title and nothing else — no
/// description, no wide backdrop, and no external id either, so the TMDB
/// fill-in that serves library items gives up on every one of them. What does
/// answer is the provider the row came from: its detail body carries the
/// overview, the 16:9 artwork and the logo, and [CatalogSourcesProvider]
/// caches every answer.
///
/// The same reasoning and the same call the spotlight used; lifted out here so
/// the detail panel is not blank on the one screen where rows are thinnest.
///
/// Items that are not catalog rows pass straight through: a library item
/// already carries its summary, and asking again would be a request for
/// nothing.
class OckerEnrichedItem extends StatefulWidget {
  final MediaItem item;

  /// [resolving] is true while a body is still on its way — the row on screen
  /// is the thin one and what it does not carry is not yet known to be
  /// missing. A surface that would otherwise draw a stand-in for a field the
  /// answer is about to fill can wait on it.
  final Widget Function(BuildContext context, MediaItem item, bool resolving) builder;

  const OckerEnrichedItem({super.key, required this.item, required this.builder});

  @override
  State<OckerEnrichedItem> createState() => _OckerEnrichedItemState();
}

class _OckerEnrichedItemState extends State<OckerEnrichedItem> {
  MediaItem? _enriched;

  /// Whether a body has been asked for and has not come back.
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(OckerEnrichedItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id == widget.item.id) return;
    _enriched = null;
    _resolve();
  }

  /// Whether the row is missing anything the panel would show.
  static bool _isThin(MediaItem item) => (item.summary ?? '').isEmpty || item.heroBackdropPaths.isEmpty;

  void _resolve() {
    _resolving = false;
    final catalogItem = widget.item.catalogItem;
    if (catalogItem == null || !_isThin(widget.item)) return;

    final sources = context.read<CatalogSourcesProvider>();

    // An answer fetched earlier is applied before the first frame that could
    // have shown the thin version.
    final known = sources.detailItemFor(catalogItem);
    if (known != null) {
      _enriched = _merge(widget.item, known, sources.detailCastFor(catalogItem));
      if ((known.overview ?? '').isEmpty) {
        appLogger.d('ocker-detail: cached body for "${widget.item.displayTitle}" carries no overview');
      }
      return;
    }

    // No debounce: the focus bus has already settled, so this runs once the
    // viewer has stopped moving, not once per tile they pass over.
    final requestedId = widget.item.id;
    _resolving = true;
    unawaited(
      sources
          .loadDetailItem(catalogItem)
          .then((detail) {
            if (!mounted || widget.item.id != requestedId) return;
            if (detail == null) {
              appLogger.d('ocker-detail: no body for "${widget.item.displayTitle}" (${catalogItem.source.name})');
              setState(() => _resolving = false);
              return;
            }
            if ((detail.overview ?? '').isEmpty) {
              appLogger.d('ocker-detail: body for "${widget.item.displayTitle}" carries no overview');
            }
            setState(() {
              _enriched = _merge(widget.item, detail, sources.detailCastFor(catalogItem));
              _resolving = false;
            });
          })
          .catchError((Object error) {
            appLogger.d('ocker-detail: lookup failed for "${widget.item.displayTitle}"', error: error);
            if (mounted) setState(() => _resolving = false);
          }),
    );
  }

  /// The row, with whatever the detail body added — and nothing taken away.
  static MediaItem _merge(MediaItem item, CatalogItem detail, List<CatalogCastMember> cast) {
    final backdrop = detail.backdropUrl ?? detail.bannerUrl;
    final logo = detail.logoUrl;
    final directors = [
      for (final credit in detail.credits ?? const <CatalogCredit>[])
        if (credit.role == CatalogCreditRole.director) credit.name,
    ];
    return item.copyWith(
      // Who made it and who is in it, for the credits at the glass panel's
      // foot — the row's own where it has them.
      directors: (item.directors ?? const []).isNotEmpty || directors.isEmpty ? item.directors : directors,
      roles: (item.roles ?? const []).isNotEmpty || cast.isEmpty
          ? item.roles
          : [for (final member in cast) MediaRole(tag: member.name, role: member.secondary)],
      artPath: (backdrop ?? '').isNotEmpty ? backdrop : item.artPath,
      backdropPaths: (backdrop ?? '').isEmpty ? item.backdropPaths : [backdrop!],
      clearLogoPath: (logo ?? '').isNotEmpty ? logo : item.clearLogoPath,
      summary: (item.summary ?? '').isNotEmpty ? item.summary : detail.overview,
      // The detail body is also where the external ids turn up — a row knows
      // its provider's key and usually nothing else. Writing the enriched
      // catalog data back means anything downstream that is keyed by TMDB or
      // IMDb (the artwork fill-in, the watchlist match) can answer for this
      // item too, where before it had nothing to look up.
      raw: {...?item.raw, CatalogItem.rawKey: detail.toJson()},
    );
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _enriched ?? widget.item, _resolving);
}
