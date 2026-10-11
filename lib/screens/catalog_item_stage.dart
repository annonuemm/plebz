import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/locked_hub_controller.dart';
import '../i18n/app_locale_utils.dart';
import '../i18n/strings.g.dart';
import '../media/media_backend.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../models/catalog/catalog_cast_member.dart';
import '../models/catalog/catalog_item.dart';
import '../models/catalog/catalog_labels.dart';
import '../models/catalog/catalog_metadata.dart';
import '../redesign/ocker_fact_card.dart';
import '../redesign/ocker_skin.dart';
import '../redesign/ocker_type.dart';
import '../theme/mono_tokens.dart';
import '../utils/country_codes.dart';
import '../utils/formatters.dart';
import '../utils/layout_constants.dart';
import '../utils/media_image_helper.dart';
import '../widgets/app_icon.dart';
import '../widgets/detail_home_button.dart';
import '../widgets/library_copy_tile.dart';
import '../widgets/tv_browse_rail.dart';
import '../widgets/tv_spotlight_background.dart';

/// The Explore detail page as the redesign's stage on a television (Plebz):
/// on a television under Glas or Flach, the layout a title from the viewer's
/// own libraries gets — the picture, the title and its facts, the buttons,
/// and rows under them (the viewer's call: the scrolling page read as a
/// stranger in the redesign).
///
/// The title area is the start page's info box over the title's picture
/// ([TvSpotlightBackground]), the buttons under it; DOWN raises the rows
/// over it, the buttons stepping out of sight as they do on a detail page,
/// and UP from the rows brings them back.
///
/// The buttons are the page's own ([buttons]), shared with the scrolling
/// page: DOWN from them is [CatalogItemStageState.focusRows], UP the home
/// button's [homeFocusNode].
class CatalogItemStage extends StatefulWidget {
  const CatalogItemStage({
    super.key,
    required this.item,
    required this.copies,
    required this.resolvingCopies,
    required this.uncheckedServers,
    required this.cast,
    required this.relations,
    required this.related,
    required this.buttons,
    required this.homeFocusNode,
    required this.onFocusButtons,
    required this.onOpenCopy,
    required this.onOpenCastMember,
  });

  final CatalogItem item;

  /// The viewer's copies, best first; null until the libraries have been
  /// asked.
  final List<MediaItem>? copies;
  final bool resolvingCopies;

  /// How many servers could not be asked.
  final int uncheckedServers;
  final List<CatalogCastMember> cast;

  /// What the title belongs to: sequels, spin-offs and the like.
  final List<CatalogItem> relations;

  /// What is like it.
  final List<CatalogItem> related;

  /// The action bar and the note under it.
  final List<Widget> buttons;
  final FocusNode homeFocusNode;

  /// Puts focus on the first button.
  final VoidCallback onFocusButtons;
  final ValueChanged<MediaItem> onOpenCopy;

  /// Null where the cast are characters (MAL, AniList): their cards open
  /// nothing.
  final ValueChanged<CatalogCastMember>? onOpenCastMember;

  @override
  State<CatalogItemStage> createState() => CatalogItemStageState();
}

class CatalogItemStageState extends State<CatalogItemStage> {
  static const _copiesHubId = 'catalog_stage_copies';
  static const _castHubId = 'catalog_stage_cast';
  static const _relationsHubId = 'catalog_stage_relations';
  static const _relatedHubId = 'catalog_stage_related';

  final _railKey = GlobalKey<TvBrowseRailState>();
  final _hubFocusMemory = HubFocusMemory();

  /// Whether the rows are up over the title area.
  bool _rowsRaised = false;

  /// What the buttons take, with the line over them and the note under them,
  /// measured after layout: the info box stands on top of it, and a guess
  /// left the description over the buttons when a note ("30 of 99 episodes")
  /// was there.
  final _buttonsKey = GlobalKey();
  double? _buttonsHeight;

  /// DOWN from the buttons.
  void focusRows() => _railKey.currentState?.requestFocus();

  void _measureButtons() {
    final box = _buttonsKey.currentContext?.findRenderObject();
    if (!mounted || box is! RenderBox || !box.hasSize) return;
    final height = box.size.height;
    if (_buttonsHeight != null && (height - _buttonsHeight!).abs() < 1) return;
    setState(() => _buttonsHeight = height);
  }

  /// The rows: the viewer's copies first, then who is in it, what it belongs
  /// to, and what is like it — the scrolling page's order.
  List<MediaHub> _hubs() {
    final hubs = <MediaHub>[];
    final copies = widget.copies ?? const <MediaItem>[];
    if (copies.isNotEmpty) {
      hubs.add(
        MediaHub(
          id: _copiesHubId,
          title: t.explore.inTheseLibraries,
          type: 'mixed',
          items: [
            for (final copy in copies)
              copy.copyWith(title: libraryCopyName(copy), parentTitle: libraryCopyServer(copy)),
          ],
          size: copies.length,
        ),
      );
    }
    final cast = widget.cast;
    if (cast.isNotEmpty) {
      hubs.add(
        MediaHub(
          id: _castHubId,
          title: const {CatalogSourceId.mal, CatalogSourceId.anilist}.contains(widget.item.source)
              ? t.explore.characters
              : t.explore.cast,
          type: 'person',
          items: [
            for (var index = 0; index < cast.length; index++)
              MediaItem(
                id: 'catalog_cast_$index',
                backend: MediaBackend.plex,
                kind: MediaKind.unknown,
                title: cast[index].name,
                parentTitle: cast[index].secondary,
                thumbPath: cast[index].imageUrl,
              ),
          ],
          size: cast.length,
        ),
      );
    }
    if (widget.relations.isNotEmpty) {
      hubs.add(
        MediaHub(
          id: _relationsHubId,
          title: t.explore.detail.relatedTitles,
          type: 'mixed',
          items: [for (final item in widget.relations) item.toMediaItem()],
          size: widget.relations.length,
        ),
      );
    }
    if (widget.related.isNotEmpty) {
      hubs.add(
        MediaHub(
          id: _relatedHubId,
          title: t.discover.moreLikeThis,
          type: 'mixed',
          items: [for (final item in widget.related) item.toMediaItem()],
          size: widget.related.length,
        ),
      );
    }
    return hubs;
  }

  IconData _hubIcon(MediaHub hub, int index) => switch (hub.id) {
    _copiesHubId => Symbols.video_library_rounded,
    _castHubId => Symbols.people_rounded,
    _relationsHubId => Symbols.link_rounded,
    _ => Symbols.recommend_rounded,
  };

  /// A copy opens on its own server and a member of the cast their page, as
  /// their rows on the scrolling page do. Catalog titles are left to the rail,
  /// which opens their own page.
  Future<bool> _activateItem(MediaHub hub, MediaItem item) async {
    if (hub.id == _copiesHubId) {
      final original = widget.copies?.firstWhereOrNull((copy) => copy.globalKey == item.globalKey);
      if (original != null) widget.onOpenCopy(original);
      return true;
    }
    if (hub.id != _castHubId) return false;
    final index = int.tryParse(item.id.substring(item.id.lastIndexOf('_') + 1));
    final open = widget.onOpenCastMember;
    if (open != null && index != null && index < widget.cast.length) open(widget.cast[index]);
    return true;
  }

  /// Over the buttons while there is no copy to name: still looking, none
  /// found, or servers that could not be asked. A copy names itself on the
  /// first button.
  Widget? _libraryStatus() {
    final tk = tokens(context);
    final style = OckerType.of(context).spotlightFacts.copyWith(color: tk.ink(0.7));
    final size = style.fontSize ?? 14;
    final copies = widget.copies;
    Widget line(Widget lead, String text) => Row(
      mainAxisSize: .min,
      children: [
        lead,
        SizedBox(width: size * 0.5),
        Flexible(
          child: Text(text, style: style, maxLines: 1, overflow: .ellipsis),
        ),
      ],
    );
    if (copies == null || (copies.isEmpty && widget.resolvingCopies)) {
      return line(
        SizedBox(width: size, height: size, child: const CircularProgressIndicator(strokeWidth: 2)),
        t.explore.checkingLibrary,
      );
    }
    if (copies.isNotEmpty) return null;
    final unchecked = widget.uncheckedServers;
    return line(
      AppIcon(
        unchecked == 0 ? Symbols.info_rounded : Symbols.cloud_off_rounded,
        fill: 1,
        size: size,
        color: tk.ink(0.7),
      ),
      unchecked == 0 ? t.explore.notInLibrary : t.explore.libraryCheckFailed(n: unchecked),
    );
  }

  /// The fact sheet: what the scrolling page lists under its overview and the
  /// info box beside it does not already say, at most seven lines of one line
  /// each — a series' run and its next episode, a film's director, writer,
  /// budget and takings, then when, where and by whom. Producers (long lists)
  /// and the content advisory (the rating is in the facts line) stay off. The
  /// viewer's call: facts behind an info button were facts nobody read. Cast
  /// stays a row.
  List<({String label, String value})> _facts() {
    final item = widget.item;
    final locale = LocaleSettings.currentLocale.intlLocaleName;
    final dateFormat = DateFormat.yMMMd(locale);
    final facts = <({String label, String value})>[];
    void add(String label, String? value) {
      if (value != null && value.trim().isNotEmpty) facts.add((label: label, value: value.trim()));
    }

    String? firstAndMore(Iterable<String>? values, {String Function(String value)? displayName}) {
      final list = [
        for (final value in values ?? const <String>[])
          if (value.trim().isNotEmpty) displayName?.call(value.trim()) ?? value.trim(),
      ];
      if (list.isEmpty) return null;
      return list.length == 1 ? list.first : '${list.first} +${list.length - 1}';
    }

    final isSeries = item.kind != MediaKind.movie;
    if (isSeries) {
      final status = item.airStatus == null ? null : statusLabel(item.airStatus!);
      final episodes = item.episodeCount == null ? null : t.explore.episodeCount(n: item.episodeCount!);
      add(t.explore.detail.status, [?status, ?episodes].join(' · '));
      if (item.nextEpisode case final next?) {
        final duration = formatDurationTextual(next.timeUntil(DateTime.now()).inMilliseconds);
        add(
          t.explore.detail.nextEpisode,
          next.episode == null ? duration : t.explore.badge.nextEpisodeIn(episode: next.episode!, duration: duration),
        );
      }
    }
    if (item.releaseDate case final date?) add(t.explore.detail.released, dateFormat.format(date.toLocal()));
    if (!isSeries) {
      for (final role in const [CatalogCreditRole.director, CatalogCreditRole.writer]) {
        add(
          creditRoleLabel(role),
          firstAndMore((item.credits ?? const []).where((c) => c.role == role).map((c) => c.name)),
        );
      }
    }
    if (isSeries && (item.network?.trim().isNotEmpty ?? false)) {
      add(t.explore.detail.networks, item.network);
    } else {
      add(t.explore.detail.studios, firstAndMore(item.studios));
    }
    add(t.explore.detail.country, firstAndMore(item.countries, displayName: CountryCodes.getDisplayName));
    if (isSeries) {
      if (item.endDate case final date?) add(t.explore.detail.ended, dateFormat.format(date.toLocal()));
    } else {
      final money = NumberFormat.compactSimpleCurrency(locale: locale, name: 'USD');
      if (item.budget case final budget?) add(t.explore.detail.budget, money.format(budget));
      if (item.revenue case final revenue?) add(t.explore.detail.revenue, money.format(revenue));
    }
    // Seven at most: a film's run of facts is longer than a series', and
    // still one line each.
    return facts.take(7).toList();
  }

  /// [_facts] on a card of their own: the picture stands behind this side of
  /// the stage.
  Widget? _factSheet() {
    final facts = _facts();
    if (facts.isEmpty) return null;
    final tk = tokens(context);
    final type = OckerType.of(context);
    final scale = ockerScale(context);
    return OckerFactCard(
      facts: [for (final fact in facts) (label: type.headingCase(fact.label), value: fact.value)],
      labelWidth: 170 * scale,
      labelStyle: type.counter.copyWith(fontSize: 15 * scale, color: tk.ink(0.55), height: 1.25),
      valueStyle: type.spotlightFacts.copyWith(fontSize: 19 * scale, color: tk.ink(0.9), height: 1.25),
      rowGap: 9 * scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final size = MediaQuery.sizeOf(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final left = (56 * scale).clamp(36.0, 72.0).toDouble();
    final viewInsets = MediaQuery.paddingOf(context);
    final backdrop = item.backdropFor(MediaImageHelper.artworkTargetPx(context, size.width, imageType: ImageType.art));
    final logo = item.logoUrl;
    final media = item.toMediaItem().copyWith(
      artPath: backdrop ?? item.backdropUrl,
      backdropPaths: backdrop == null ? null : [backdrop],
      clearLogoPath: logo != null && logo.isNotEmpty ? logo : null,
    );
    final hubs = _hubs();
    final raised = _rowsRaised && hubs.isNotEmpty;
    // The rows take the lower half; their posters at the start page's size.
    final railTop = size.height * 0.5;
    // What stands under the info box: the line on the copies, the buttons,
    // and the note under them — as high off the foot as a detail page holds
    // its buttons.
    final buttonsBottom = 96 * scale;
    final status = _libraryStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureButtons());
    final belowInfo = buttonsBottom + (_buttonsHeight ?? 52 * scale) + 12 * scale;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220);

    return Stack(
      fit: StackFit.expand,
      children: [
        TvSpotlightBackground(
          item: media,
          client: null,
          compact: true,
          contentLeft: left,
          contentTop: viewInsets.top + 72 * scale,
          contentBottom: raised ? size.height - railTop + 16 * scale : belowInfo,
          cornerProgress: raised ? 1 : 0,
          // The title area to itself has the room a detail page gives its
          // description; under the rows, the start page's three lines.
          summaryMaxLines: raised ? 3 : 6,
        ),
        Positioned(
          left: left,
          right: size.width * 0.4,
          bottom: buttonsBottom,
          // Out of sight rather than out of the tree while the rows are up:
          // UP from them focuses the first button.
          child: Offstage(
            offstage: raised,
            child: Column(
              key: _buttonsKey,
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                if (status != null) ...[status, SizedBox(height: 12 * scale)],
                ...widget.buttons,
              ],
            ),
          ),
        ),
        if (_factSheet() case final sheet?)
          Positioned(
            right: left,
            bottom: buttonsBottom,
            width: size.width * 0.34,
            // With the buttons: under the rows the info box keeps the room.
            child: Offstage(offstage: raised, child: sheet),
          ),
        if (hubs.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10 * scale,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: raised ? 0 : 1,
                duration: duration,
                child: Center(
                  child: AppIcon(
                    Symbols.keyboard_arrow_down_rounded,
                    size: 28 * scale,
                    color: tokens(context).ink(0.5),
                  ),
                ),
              ),
            ),
          ),
        // Parked below the edge until focus goes down, and still laid out,
        // so DOWN from the buttons reaches it.
        AnimatedPositioned(
          duration: duration,
          curve: Curves.easeOutCubic,
          left: 0,
          right: 0,
          top: raised ? railTop : size.height,
          height: size.height - railTop,
          child: Focus(
            skipTraversal: true,
            onFocusChange: (hasFocus) {
              if (hasFocus == _rowsRaised) return;
              setState(() => _rowsRaised = hasFocus);
            },
            child: hubs.isEmpty
                ? const SizedBox.shrink()
                : TvBrowseRail(
                    key: _railKey,
                    hubs: hubs,
                    focusMemory: _hubFocusMemory,
                    iconForHub: _hubIcon,
                    onActivateItem: _activateItem,
                    onNavigateUp: widget.onFocusButtons,
                    onBack: () => unawaited(Navigator.of(context).maybePop()),
                    // The copies keep their library and server visible under
                    // the card, as on a detail page.
                    fullCardLayoutForHub: (hub) => hub.id == _copiesHubId ? false : null,
                    tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
                    contentLeft: left,
                  ),
          ),
        ),
        Positioned(
          top: viewInsets.top + 20 * scale,
          left: left,
          child: DetailHomeButton(focusNode: widget.homeFocusNode, onNavigateDown: widget.onFocusButtons),
        ),
      ],
    );
  }
}
