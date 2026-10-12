part of '../media_detail_screen.dart';

// Plebz's own share of the detail page: the person page from the cast, the
// other copies of a title, the television header's title and facts under the
// redesigns, and the season tabs. Kept out of upstream's file so a merge meets
// its own code there and ours here; the state's fields, the overrides and
// upstream's own methods stay in the class.

/// How tall the tab row stands over the rows, in the detail page's scale:
/// the bar at its foot, and the room above it that parts it from the
/// buttons. More above than below, so the tabs read with the episodes they
/// choose rather than with the buttons (the viewer's call).
const double _tvDetailSeasonTabsHeight = 62;

/// How much of the hero's width the corner backdrop keeps.
///
/// The spotlight's own fraction ([cornerBackdropSize]), so a title looks the
/// same on the way in as it did on the row it was opened from.
const double _cornerHeroWidthFraction = 0.68;

/// Whether the viewer has switched Dolby Vision off. The facts line then names
/// the base layer that actually reaches the display instead of DV.
bool get _dolbyVisionDisabled => SettingsService.instance.read(PlebzPrefs.disableDolbyVision);

/// Clips at the top edge only, and lets whatever is drawn reach [reach]
/// past the other three.
class _ClipTopOnly extends CustomClipper<Rect> {
  const _ClipTopOnly({required this.reach});

  final double reach;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-reach, 0, size.width + reach, size.height + reach);

  @override
  bool shouldReclip(_ClipTopOnly oldClipper) => oldClipper.reach != reach;
}

extension _MediaDetailFork on _MediaDetailScreenState {
  // The person page from the cast

  /// With a Plex account a person opens on the page Explore's cast opens:
  /// Plex's whole filmography, the titles on every server first. Without one
  /// the server's own list stays, which needs no account: false, for the
  /// caller to open that.
  bool _openActorOnPlexPage(MediaRole actor) {
    if (!plexPersonPageAvailable(context) || actor.tag.trim().isEmpty) return false;
    unawaited(
      navigateToCatalogPerson(
        context,
        name: actor.tag,
        personId: actor.discoverId,
        thumbUrl: actor.thumbPath,
        characterName: actor.role,
        sourceTitle: _metadata.displayTitle,
      ),
    );
    return true;
  }

  // The watchlist

  /// Kept by the app because the provider did not know the title then; it
  /// does now, so the title goes where it belongs.
  Future<void> _promoteLocalWatchlistEntry(List<WatchlistCandidate> candidates) async {
    final local = _localWatchlist;
    if (local == null || !local.holds(_metadata)) return;
    for (final candidate in candidates) {
      await local.promote(_metadata, candidate);
    }
  }

  // Other copies of the title

  FocusNode _otherCopyFocusNode(MediaItem copy) =>
      _otherCopyFocusNodes.putIfAbsent(copy.globalKey, () => FocusNode(debugLabel: 'other_copy_${copy.globalKey}'));

  /// Look this title up on every online server, so the page can say where
  /// else it exists and in what quality.
  ///
  /// With a single server online too (Plebz): the server's own lookup spans
  /// all its libraries, so a copy in another one — "Filme" and "Filme - 4K" —
  /// is found there. It costs a few requests per page open; the viewer wanted
  /// the comparison on a one-server setup.
  Future<void> _loadOtherServerCopies() async {
    final metadata = _fullMetadata ?? _metadata;
    if (widget.isOffline || !(metadata.isMovie || metadata.isShow)) return;

    // Nullable read: hosts without the provider (widget tests) simply never
    // show the section, mirroring how the watchlist action resolves.
    final multiServer = Provider.of<MultiServerProvider?>(context, listen: false);
    if (multiServer == null || multiServer.serverManager.onlineClients.isEmpty) return;

    final serverId = serverIdOrNull(metadata.serverId);
    final client = serverId == null ? null : multiServer.serverManager.getClient(serverId);
    if (client == null) return;

    try {
      final ids = await client.fetchExternalIds(metadata.id);
      if (!mounted) return;
      // Every visible server: the point of the section is the copies that are
      // somewhere other than here.
      final lookup = await multiServer.aggregationService.findByExternalIdsAcrossServers(
        ids,
        kind: metadata.kind,
        serverIds: multiServer.serverIds.toSet(),
        titles: [?metadata.title],
        year: metadata.year,
        plexGuid: metadata.guid,
      );
      if (!mounted) return;
      setStateIfMounted(() {
        // The copy being looked at is already described by the rest of the
        // page; the section is about everywhere else.
        _otherCopies = [
          for (final copy in lookup.items)
            if (copy.globalKey != metadata.globalKey) copy,
        ];
      });
    } catch (error, stackTrace) {
      appLogger.d('Other-server lookup failed for ${metadata.globalKey}', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      // A failed wave is not evidence that no other copy exists, but the
      // section has nothing to show either way.
      setStateIfMounted(() => _otherCopies = const []);
    }
  }

  /// Also available on — other libraries holding a copy of this title, and
  /// the server each is on: the scrolling page's section, its heading in
  /// [titleStyle]. Nothing while there is no other copy.
  List<Widget> _otherCopiesSection(BuildContext context, TextStyle? titleStyle) {
    final copies = _otherCopies;
    if (copies == null || copies.isEmpty) return const [];
    return [
      Text(t.discover.alsoAvailableOn, style: titleStyle),
      const SizedBox(height: 12),
      SettingsGroup(
        margin: EdgeInsets.zero,
        children: [
          for (final copy in copies)
            LibraryCopyTile(
              copy: copy,
              showsQuality: false,
              focusNode: _otherCopyFocusNode(copy),
              onTap: () => unawaited(navigateToMediaItemDetails(context, copy)),
            ),
        ],
      ),
      const SizedBox(height: 24),
    ];
  }

  /// A copy rendered for the rail: the card names the library it sits in and,
  /// underneath, the quality it has there — the two things that tell copies
  /// apart. Ids are untouched, so the row still resolves to the real copy.
  MediaItem _tvDetailOtherCopyItem(MediaItem copy) =>
      copy.copyWith(title: libraryCopyName(copy), parentTitle: libraryCopyServer(copy));

  /// Other libraries holding this title, on a television. The page has no
  /// section stack there — it is rails all the way down — so they become a
  /// rail whose cards name the library and, under it, the server it is on,
  /// mirroring the phone section. No quality there: the poster's own badges
  /// carry it.
  MediaHub? _tvDetailOtherCopiesHub() {
    final copies = _otherCopies;
    if (copies == null || copies.isEmpty) return null;
    return MediaHub(
      id: _tvDetailOtherCopiesHubId,
      title: t.discover.alsoAvailableOn,
      type: 'mixed',
      items: [for (final copy in copies) _tvDetailOtherCopyItem(copy)],
      size: copies.length,
    );
  }

  /// A card of the copies rail opens its copy — the untouched one, not the
  /// display item, so the page it opens carries the real title rather than
  /// the library name.
  Future<bool> _openTvDetailOtherCopy(MediaItem item) async {
    final original = _otherCopies?.firstWhereOrNull((copy) => copy.globalKey == item.globalKey);
    if (original != null) await navigateToMediaItemDetails(context, original);
    return true;
  }

  /// The copies rail opts out of the label-free card treatment (see the rail's
  /// `fullCardLayoutForHub`). Declared once so the rail and the height estimate
  /// below cannot disagree — if they did, the rail would overlap the summary.
  bool? _tvDetailFullCardLayoutForHub(MediaHub hub) => hub.id == _tvDetailOtherCopiesHubId ? false : null;

  // The television header under the redesigns

  /// The page title under "Flach": the start page's title, set tight, with no
  /// halo — the scrims carry the contrast.
  Widget _flachDetailTitle(
    BuildContext context,
    String title, {
    double? fontSize,
    Color? color,
    TextAlign? textAlign,
    Alignment? alignment,
  }) {
    final size = fontSize ?? Theme.of(context).textTheme.displaySmall?.fontSize ?? 36;
    return FittingTitleText(
      title,
      style: OckerType.of(context).spotlightTitle().copyWith(
        color: color ?? Theme.of(context).colorScheme.onSurface,
        fontSize: size,
        letterSpacing: -0.027 * size,
      ),
      textAlign: textAlign,
      alignment: alignment ?? (textAlign == TextAlign.center ? Alignment.center : Alignment.centerLeft),
    );
  }

  /// The halo behind the title set as type: dark on a dark theme, light on
  /// a light one.
  Color _tvDetailTitleShadowColor(BuildContext context) {
    final brightness = Theme.of(context).colorScheme.brightness;
    return brightness == Brightness.dark ? Colors.black.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.55);
  }

  /// How many lines [description] fills at [width], capped at the ceiling.
  ///
  /// Laid out with the same style the summary is drawn with, so the count is
  /// the one the screen will show rather than an estimate.
  int _tvDetailSummaryLineCount(BuildContext context, String description, TvDetailHeaderMetrics metrics, double width) {
    if (width <= 0) return metrics.summaryLineCeiling;
    final painter = TextPainter(
      text: TextSpan(
        text: description,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: metrics.summaryFontSize, height: 1.35),
      ),
      maxLines: metrics.summaryLineCeiling,
      textDirection: Directionality.of(context),
    )..layout(maxWidth: width);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines == 0 ? 1 : lines;
  }

  /// The page's title: the clear logo where it fits, otherwise type.
  ///
  /// Built once and placed by the caller — above the facts in the fixed
  /// layout, in its own top-left band while the title area owns the screen.
  /// [logoWidth] frames a clear logo — narrow on purpose, so a wide wordmark
  /// stays a title instead of becoming a banner across the artwork.
  /// [titleWidth] is what the name gets when it has to be set as type: a
  /// wordmark carries at a size a sentence of letters cannot, and squeezed
  /// into the logo's box a long title either shrank to nothing or broke
  /// across two lines mid-word.
  Widget _tvDetailTitleBlock(
    BuildContext context,
    MediaItem metadata,
    TvDetailHeaderLayout layout,
    double logoWidth,
    double titleWidth,
    Color foregroundColor,
  ) {
    if (layout.titleMode == TvDetailTitleMode.logo) {
      return _buildDetailLogoOrTitle(
        context,
        metadata,
        width: logoWidth,
        fallbackWidth: titleWidth,
        height: layout.titleHeight,
        // A logo on the floor of its box, as the type that stands in for it.
        alignment: Alignment.bottomLeft,
        titleBuilder: (context, title) =>
            _tvDetailTextTitle(context, title, fontSize: layout.titleFontSize, foregroundColor: foregroundColor),
      );
    }
    // No logo even where the server has one: the height it needs is a line of
    // summary, and this box is sized for type.
    return SizedBox(
      width: titleWidth,
      height: layout.titleHeight,
      child: Align(
        alignment: .bottomLeft,
        child: _tvDetailTextTitle(
          context,
          metadata.displayTitle,
          fontSize: layout.titleFontSize,
          foregroundColor: foregroundColor,
        ),
      ),
    );
  }

  /// The page title set as type, at whatever size its box allows.
  Widget _tvDetailTextTitle(
    BuildContext context,
    String title, {
    required double fontSize,
    required Color foregroundColor,
  }) => _buildDetailTitle(
    context,
    title,
    fontSize: fontSize,
    fontWeight: .w800,
    shadowBlur: 12,
    color: foregroundColor,
    shadowColor: _tvDetailTitleShadowColor(context),
    // On the floor of its box, in every theme: a one-line title centred in a
    // box sized for two stood a line's height away from the facts below it.
    alignment: Alignment.bottomLeft,
  );

  /// Whether the facts take a second row for the picture and sound: on a page
  /// of something to watch, in every theme — "Glas" had it first, and the
  /// original look took it over at the user's word.
  ///
  /// Budgeted for the page, not for the moment — as the episode title is. The
  /// picture and sound are only known once the playback source has resolved,
  /// after the header has been laid out; a row that arrived then would push
  /// everything below it out of the budget.
  ///
  /// Not in the redesigns while the rows are raised ([_tvDetailOneFactsRow]).
  bool _tvDetailReservesQualityRow(BuildContext context, MediaItem metadata, {required bool titleAreaExpanded}) =>
      !_tvDetailOneFactsRow(context, titleAreaExpanded: titleAreaExpanded) &&
      (metadata.isMovie || metadata.isShow || metadata.isSeason || metadata.isEpisode);

  /// Both redesigns with the rows raised (Plebz): one row of facts, the
  /// picture and sound in it beside the episode's own and the bitrate left
  /// out — the room the second row took goes to the description. The title
  /// area, open, keeps both rows and the bitrate (the viewer's call).
  bool _tvDetailOneFactsRow(BuildContext context, {required bool titleAreaExpanded}) =>
      !titleAreaExpanded && ockerGlass(context);

  /// "Flach" with the rows raised (Plebz): the title at the start page's size
  /// — a line of its title, as the spotlight sets it — so the summary keeps
  /// its lines; with the title area to itself it stays large. Glas too, on
  /// Flach's sizes ([ockerFlatSizes]).
  double? _tvDetailRaisedTitleCap(BuildContext context, {required bool heroLayout}) {
    if (heroLayout || !ockerFlatSizes(context)) return null;
    return (OckerType.of(context).spotlightTitle().fontSize ?? 30) * 1.2;
  }

  /// Either redesign with the rows raised (Plebz): the action row steps out of
  /// sight — see [TvDetailHeaderMetrics.hidesActions].
  bool _tvDetailHidesActions(BuildContext context, {required bool titleAreaExpanded}) =>
      !titleAreaExpanded && ockerGlass(context);

  /// Glas's header on the start page's sizes (Plebz): see
  /// [TvDetailHeaderMetrics.compactGlass].
  bool _tvDetailCompactGlass(BuildContext context) => ockerFlatSizes(context) && !ockerFlat(context);

  // Season tabs

  /// Whether the redesign on show has its season tabs switched on (Plebz):
  /// one switch each for Glas and "Flach", both off to start with — a row per
  /// season, one under the other.
  bool get _tvDetailSeasonTabsOn =>
      ockerGlass(context) &&
      (SettingsService.instanceOrNull?.read(PlebzPrefs.seasonTabsFor(flat: ockerFlat(context))) ?? false);

  /// On a television (Plebz): whether the seasons stand as a row of tabs over
  /// the one row of episodes — a show of two seasons or more, where
  /// [_tvDetailSeasonTabsOn].
  bool _tvDetailUsesSeasonTabs(MediaItem metadata) =>
      _tvDetailSeasonTabsOn && metadata.isShow && !_showEpisodesDirectly && !_seasonsLoadFailed && _seasons.length > 1;

  /// Under season tabs (a switch in either redesign): the one row of the
  /// chosen season's episodes, under a row of season tabs of its own (see
  /// [_withTvDetailSeasonTabs]) — not a row per season. A show of many seasons
  /// is then two rows to pass, not one per season, going down and coming back
  /// up (the viewer's call). The page still opens on the season and the
  /// episode to go on with: [_selectedSeasonIndex] is that season from the
  /// start.
  MediaHub _tvDetailSeasonTabHub() {
    final season = _seasons[_selectedSeasonIndex.clamp(0, _seasons.length - 1)];
    final state = _seasonEpisodePager.stateFor(season.id);
    final total = state.totalCount > _episodes.length ? state.totalCount : (season.leafCount ?? _episodes.length);
    return MediaHub(
      id: '$_tvDetailSeasonHubIdPrefix$_selectedSeasonIndex',
      title: _tvDetailSeasonLabel(season),
      type: 'episode',
      items: _episodes,
      size: total,
    );
  }

  /// The tab of the season on show.
  void _focusTvDetailSeasonTab() {
    _updateSeasonTabFocusNodes(_seasons.length);
    if (_seasons.isEmpty) return _focusTvDetailActionRow();
    final index = _selectedSeasonIndex.clamp(0, _seasons.length - 1);
    _tvDetailActionRowHasFocus = false;
    _clearTvDetailFocusedEpisode();
    _seasonTabFocusNodes[index].requestFocus();
  }

  /// [rail] under the season tabs where [show] says so — a row of its own
  /// just above the rows, low and plain, so the tabs and the episodes are on
  /// screen together. The rows used to give every row the same height, and a
  /// row of tabs among them stood as tall as a row of episodes (the viewer's
  /// call).
  ///
  /// UP from a tab is the buttons, DOWN the episodes; LEFT and RIGHT choose
  /// the season next door, and the row under them follows at once.
  Widget _withTvDetailSeasonTabs({
    required bool show,
    required double scale,
    required double left,
    required Widget rail,
  }) {
    if (!show) return rail;
    _updateSeasonTabFocusNodes(_seasons.length);
    void choose(int index) {
      if (index < 0 || index >= _seasons.length) return;
      _selectTvDetailSeason(index);
      _seasonTabFocusNodes[index].requestFocus();
      _scrollSeasonTabIntoView(index);
    }

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        SizedBox(
          key: const ValueKey('tv_detail_season_tabs'),
          height: _tvDetailSeasonTabsHeight * scale,
          child: Padding(
            // The bar's own edge, not its first word, in line with the buttons
            // above it and the rows under it.
            padding: EdgeInsets.only(
              left: left + TabChipStrip.overhangOf(context).left,
              right: TvBrowseRailLayout.horizontalInsetForScale(scale),
            ),
            child: Align(
              alignment: .bottomLeft,
              child: TabChipStrip(
                children: [
                  for (var i = 0; i < _seasons.length; i++)
                    FocusableTabChip(
                      label: _tvDetailSeasonLabel(_seasons[i]),
                      isSelected: i == _selectedSeasonIndex,
                      focusNode: _seasonTabFocusNodes[i],
                      onSelect: () => choose(i),
                      onNavigateLeft: i > 0 ? () => choose(i - 1) : null,
                      onNavigateRight: i < _seasons.length - 1 ? () => choose(i + 1) : null,
                      onNavigateDown: () => _tvDetailRailKey.currentState?.requestFocus(),
                      onNavigateUp: _focusTvDetailActionRow,
                      onBack: _popMediaDetailIfBackNotSuppressed,
                    ),
                ],
              ),
            ),
          ),
        ),
        rail,
      ],
    );
  }

  /// A season's name in a row's heading or on its tab.
  String _tvDetailSeasonLabel(MediaItem season) =>
      season.title?.isNotEmpty == true ? season.title! : (season.displaySubtitle ?? season.displayTitle);
}
