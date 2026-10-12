import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../focus/focusable_action_bar.dart';
import '../focus/key_event_utils.dart';
import '../i18n/app_locale_utils.dart';
import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../mixins/grid_focus_node_mixin.dart';
import '../models/catalog/catalog_item.dart';
import '../models/catalog/catalog_person.dart';
import '../providers/catalog_sources_provider.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../redesign/ocker_skin.dart';
import '../services/catalog/plex_catalog_source.dart';
import '../theme/mono_theme.dart';
import '../theme/mono_tokens.dart';
import '../utils/app_logger.dart';
import '../utils/dialogs.dart';
import '../utils/media_image_helper.dart';
import '../utils/platform_detector.dart';
import '../widgets/collapsible_text.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/focusable_tab_chip.dart';
import '../widgets/loading_indicator_box.dart';
import '../widgets/optimized_media_image.dart';
import '../widgets/overlay_sheet.dart';
import 'catalog_person_stage.dart';
import 'focusable_detail_screen_mixin.dart';
import 'libraries/content_state_builder.dart';

/// Whether a person opens on [CatalogPersonScreen] rather than a server's own
/// list: the page's filmography comes from Plex Discover, so it needs the Plex
/// account. Without one, callers open `navigateToPersonMedia`, which needs none.
bool plexPersonPageAvailable(BuildContext context) =>
    context.read<CatalogSourcesProvider?>()?.connectedSources.any((source) => source.id == CatalogSourceId.plex) ??
    false;

/// Opens [CatalogPersonScreen] for a cast member of an Explore page.
Future<void> navigateToCatalogPerson(
  BuildContext context, {
  required String name,
  String? personId,
  String? thumbUrl,
  String? characterName,
  String? sourceTitle,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => CatalogPersonScreen(
        name: name,
        personId: personId,
        thumbUrl: thumbUrl,
        characterName: characterName,
        sourceTitle: sourceTitle,
      ),
    ),
  );
}

/// The filter over a person's titles: everything, films, series, or guest
/// appearances as themselves.
enum PersonTitleTab { all, movies, shows, appearances }

/// Whether a title of [kind] belongs under [tab]; [appearance] marks a guest
/// spot, which only "Auftritte" lists — "Alle" too, as the whole.
bool personTitleInTab(PersonTitleTab tab, {required MediaKind kind, required bool appearance}) => switch (tab) {
  PersonTitleTab.all => true,
  PersonTitleTab.movies => !appearance && kind == MediaKind.movie,
  PersonTitleTab.shows => !appearance && kind == MediaKind.show,
  PersonTitleTab.appearances => appearance,
};

/// The filter by whether a title is on the viewer's servers.
enum PersonAvailability { all, available, missing }

/// A title on the viewer's servers, with the credit it answers for where the
/// filmography names it.
typedef PersonOwnedTitle = ({MediaItem item, CatalogPersonCredit? credit});

/// A person's page as Plex shows it (Plebz): portrait, life dates and
/// biography from Plex Discover, then their titles — first the ones in the
/// viewer's libraries, then everything else they are credited in, which opens
/// the Explore page for that title — under a filter by kind.
///
/// On a television under Glas or Flach it stands as the redesign's stage
/// ([CatalogPersonStage]); everywhere else as a scrolling page.
///
/// Reached from Explore, whose cast is Discover's: [personId] is Discover's id
/// when the source supplied one, and is looked up by [name] otherwise. The
/// libraries know people by name only, so that is what they are asked for.
class CatalogPersonScreen extends StatefulWidget {
  final String name;
  final String? personId;
  final String? thumbUrl;
  final String? characterName;

  /// The title the person was reached from, for "als … in „…“".
  final String? sourceTitle;

  const CatalogPersonScreen({
    super.key,
    required this.name,
    this.personId,
    this.thumbUrl,
    this.characterName,
    this.sourceTitle,
  });

  @override
  State<CatalogPersonScreen> createState() => _CatalogPersonScreenState();
}

class _CatalogPersonScreenState extends State<CatalogPersonScreen>
    with GridFocusNodeMixin<CatalogPersonScreen>, FocusableDetailScreenMixin<CatalogPersonScreen> {
  final _stageKey = GlobalKey<CatalogPersonStageState>();
  final _stageScroll = ScrollController();

  CatalogPerson? _person;
  List<PersonOwnedTitle> _owned = const [];
  List<CatalogPersonCredit> _others = const [];
  PersonTitleTab _tab = PersonTitleTab.all;
  PersonAvailability _availability = PersonAvailability.all;
  bool _loading = true;
  final List<FocusNode> _tabNodes = [
    for (final tab in PersonTitleTab.values) FocusNode(debugLabel: 'person_tab_${tab.name}'),
  ];
  final List<FocusNode> _availabilityNodes = [
    for (final value in PersonAvailability.values) FocusNode(debugLabel: 'person_availability_${value.name}'),
  ];

  @override
  bool get hasItems => _visibleOwned.isNotEmpty || _visibleOthers.isNotEmpty;

  @override
  List<FocusableAction> getAppBarActions() => const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final node in [..._tabNodes, ..._availabilityNodes]) {
      node.dispose();
    }
    _stageScroll.dispose();
    disposeFocusResources();
    super.dispose();
  }

  Future<void> _load() async {
    final plex = context.read<CatalogSourcesProvider>().connectedSources.whereType<PlexCatalogSource>().firstOrNull;
    final multiServer = context.read<MultiServerProvider>();
    final hiddenLibraries = context.read<HiddenLibrariesProvider?>();

    final ownedFuture = () async {
      try {
        await hiddenLibraries?.ensureInitialized();
        return await multiServer.aggregationService.findPersonTitlesAcrossServers(
          widget.name,
          hiddenLibraryKeys: hiddenLibraries?.hiddenLibraryKeys,
        );
      } catch (error, stackTrace) {
        appLogger.w('Person page: library titles failed', error: error, stackTrace: stackTrace);
        return const <MediaItem>[];
      }
    }();

    CatalogPerson? person;
    var credits = const <CatalogPersonCredit>[];
    if (plex != null) {
      try {
        final personId = widget.personId ?? await plex.findPersonId(widget.name);
        if (personId != null) {
          final personFuture = plex.fetchPerson(personId, fallbackName: widget.name);
          final creditsFuture = plex.fetchPersonCredits(personId);
          person = await personFuture.catchError((Object error) {
            appLogger.d('Person page: Discover record failed', error: error);
            return null;
          });
          credits = await creditsFuture;
        }
      } catch (error, stackTrace) {
        appLogger.w('Person page: Discover filmography failed', error: error, stackTrace: stackTrace);
      }
    }

    final owned = await ownedFuture;
    if (!mounted) return;
    final split = splitPersonTitles(owned: owned, credits: credits);
    setState(() {
      _person = person;
      _owned = split.owned;
      _others = split.others;
      _loading = false;
    });
    if (!_usesStage(context)) autoFocusFirstItemAfterLoad();
  }

  bool _usesStage(BuildContext context) => PlatformDetector.isTV() && isOckerLayout(context);

  bool _ownedInTab(PersonOwnedTitle title, PersonTitleTab tab) =>
      personTitleInTab(tab, kind: title.item.kind, appearance: title.credit?.isAppearance ?? false);

  bool _creditInTab(CatalogPersonCredit credit, PersonTitleTab tab) =>
      personTitleInTab(tab, kind: credit.item.kind, appearance: credit.isAppearance);

  List<PersonOwnedTitle> _ownedIn(PersonTitleTab tab, PersonAvailability availability) => [
    if (availability != PersonAvailability.missing)
      for (final title in _owned)
        if (_ownedInTab(title, tab)) title,
  ];

  List<CatalogPersonCredit> _othersIn(PersonTitleTab tab, PersonAvailability availability) => [
    if (availability != PersonAvailability.available)
      for (final credit in _others)
        if (_creditInTab(credit, tab)) credit,
  ];

  List<PersonOwnedTitle> get _visibleOwned => _ownedIn(_tab, _availability);

  List<CatalogPersonCredit> get _visibleOthers => _othersIn(_tab, _availability);

  /// Titles under [tab] given the availability filter (or all of them).
  int _countFor(PersonTitleTab tab, [PersonAvailability? availability]) =>
      _ownedIn(tab, availability ?? _availability).length + _othersIn(tab, availability ?? _availability).length;

  int _availabilityCount(PersonAvailability availability) =>
      _ownedIn(_tab, availability).length + _othersIn(_tab, availability).length;

  String _tabLabel(PersonTitleTab tab) => switch (tab) {
    PersonTitleTab.all => t.libraries.groupings.all,
    PersonTitleTab.movies => t.libraries.groupings.movies,
    PersonTitleTab.shows => t.libraries.groupings.shows,
    PersonTitleTab.appearances => t.actor.appearances,
  };

  String _availabilityLabel(PersonAvailability availability) => switch (availability) {
    PersonAvailability.all => t.actor.availability.all,
    PersonAvailability.available => t.actor.availability.available,
    PersonAvailability.missing => t.actor.availability.missing,
  };

  /// The kinds worth offering: "Alle" always, the others where the person
  /// has any title of them.
  List<PersonTitleTab> get _tabs => [
    for (final tab in PersonTitleTab.values)
      if (tab == PersonTitleTab.all || _countFor(tab, PersonAvailability.all) > 0) tab,
  ];

  /// The availability filter only where there is something on both sides.
  bool get _offersAvailability => _owned.isNotEmpty && _others.isNotEmpty;

  void _selectTab(PersonTitleTab tab) {
    if (tab != _tab) setState(() => _tab = tab);
  }

  void _selectAvailability(PersonAvailability availability) {
    if (availability != _availability) setState(() => _availability = availability);
  }

  void _focusFilters() => _tabNodes[_tab.index].requestFocus();

  String? _roleLine() {
    final role = widget.characterName?.trim();
    if (role == null || role.isEmpty) return null;
    final title = widget.sourceTitle?.trim();
    return title == null || title.isEmpty ? t.actor.asRole(role: role) : t.actor.asRoleIn(role: role, title: title);
  }

  String? _lifeLine() {
    final person = _person;
    if (person == null) return null;
    final format = DateFormat.yMMMMd(LocaleSettings.currentLocale.intlLocaleName);
    final born = person.bornAt;
    final place = person.birthPlace;
    final parts = [
      if (born != null && place != null)
        t.actor.bornIn(date: format.format(born), place: place)
      else if (born != null)
        t.actor.bornOn(date: format.format(born))
      else if (place != null)
        '* $place',
      if (person.diedAt case final died?) '† ${format.format(died)}',
    ];
    return parts.isEmpty ? null : parts.join('   ');
  }

  static String? _departmentLabel(String department) => switch (department.toLowerCase()) {
    'actor' || 'acting' => t.actor.departments.acting,
    'director' || 'directing' => t.actor.departments.directing,
    'producer' || 'production' => t.actor.departments.production,
    'writer' || 'writing' => t.actor.departments.writing,
    _ => null,
  };

  String? _departmentsLine() {
    final labels = <String>{
      for (final department in _person?.departments ?? const <String>[]) ?_departmentLabel(department),
    };
    return labels.isEmpty ? null : labels.join('  ·  ');
  }

  List<({String label, String value})> _facts() {
    final person = _person;
    final format = DateFormat.yMMMMd(LocaleSettings.currentLocale.intlLocaleName);
    final knownFor = person?.knownFor;
    final onPlex = _others.length + _owned.where((title) => title.credit != null).length;
    return [
      if (person?.bornAt case final born?) (label: t.actor.born, value: format.format(born)),
      if (person?.birthPlace case final place?) (label: t.actor.birthPlace, value: place),
      if (knownFor != null) (label: t.actor.knownFor, value: _departmentLabel(knownFor) ?? knownFor),
      if (onPlex > 0) (label: t.actor.titlesOnPlex, value: '$onPlex'),
      if (_owned.isNotEmpty) (label: t.actor.inLibraries, value: t.discover.titleCount(n: _owned.length)),
    ];
  }

  void _openBiography() {
    final summary = _person?.summary;
    if (summary == null) return;
    unawaited(showFullTextDialog(context, title: _person?.name ?? widget.name, text: summary));
  }

  // ---------------------------------------------------------------- stage

  /// Posters per row on the stage, whatever the library density (the
  /// viewer's call: six fit the page better than the grids' five).
  static const _stageColumns = 6;

  /// The card's second line names the role.
  static MediaItem _withRole(MediaItem item, String? role) => role == null ? item : item.copyWith(parentTitle: role);

  /// Both sections as slivers: the titles on the servers, then the rest,
  /// each under its heading. On the stage the posters keep their labels —
  /// the role is the point of the page — and stand in from the stage's edge.
  List<Widget> _gridSlivers({required bool stage}) {
    final owned = [for (final title in _visibleOwned) _withRole(title.item, title.credit?.role)];
    final others = [for (final credit in _visibleOthers) _withRole(credit.item.toMediaItem(), credit.role)];
    final s = stage ? ockerScale(context) : 1.0;
    Widget inset(Widget grid) => stage
        ? SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 112 * s),
            sliver: grid,
          )
        : grid;
    Widget heading(String text, int count) => stage ? _stageHeading(text, count, s) : _sectionTitle(text);
    return [
      if (owned.isNotEmpty) ...[
        heading(t.actor.inLibraries, owned.length),
        inset(
          buildFocusableGrid(
            items: owned,
            onRefresh: _replaceItem,
            fullCardLayout: stage ? false : null,
            columnCount: stage ? _stageColumns : null,
          ),
        ),
      ],
      if (others.isNotEmpty) ...[
        heading(t.actor.otherTitles, others.length),
        inset(
          buildFocusableGrid(
            items: others,
            onRefresh: (_) {},
            indexOffset: owned.length,
            fullCardLayout: stage ? false : null,
            columnCount: stage ? _stageColumns : null,
          ),
        ),
      ],
    ];
  }

  Widget _stageHeading(String text, int count, double s) {
    final tk = tokens(context);
    final style = TextStyle(fontFamily: ockerUiFontFamily, fontSize: 27 * s, fontWeight: .w600, color: tk.ink(1));
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(120 * s, 20 * s, 120 * s, 4 * s),
        child: Text.rich(
          TextSpan(
            text: text,
            children: [
              TextSpan(
                text: '   $count',
                style: style.copyWith(fontWeight: .w400, color: tk.ink(0.5)),
              ),
            ],
          ),
          style: style,
        ),
      ),
    );
  }

  /// The two filter strips side by side: the kinds, and — where the person
  /// has titles on both sides — whether they are on the servers.
  Widget _filters({required bool stage}) {
    final tabs = _tabs;
    final availabilities = _offersAvailability ? PersonAvailability.values : const <PersonAvailability>[];
    final upFromFilters = stage ? () => _stageKey.currentState?.focusAboveFilters() : null;
    final back = stage ? () => unawaited(Navigator.of(context).maybePop()) : null;
    void down() {
      if (hasItems) navigateToGrid();
    }

    final kindChips = [
      for (var i = 0; i < tabs.length; i++) ...[
        if (i > 0 && !stage) const SizedBox(width: 8),
        FocusableTabChip(
          label: '${_tabLabel(tabs[i])}  ${_countFor(tabs[i])}',
          isSelected: tabs[i] == _tab,
          focusNode: _tabNodes[tabs[i].index],
          onSelect: () => _selectTab(tabs[i]),
          onNavigateLeft: i > 0 ? _tabNodes[tabs[i - 1].index].requestFocus : null,
          onNavigateRight: i < tabs.length - 1
              ? _tabNodes[tabs[i + 1].index].requestFocus
              : availabilities.isNotEmpty
              ? _availabilityNodes[_availability.index].requestFocus
              : null,
          onNavigateDown: down,
          onNavigateUp: upFromFilters,
          onBack: back,
        ),
      ],
    ];
    final availabilityChips = [
      for (var i = 0; i < availabilities.length; i++) ...[
        if (i > 0 && !stage) const SizedBox(width: 8),
        FocusableTabChip(
          label: '${_availabilityLabel(availabilities[i])}  ${_availabilityCount(availabilities[i])}',
          isSelected: availabilities[i] == _availability,
          focusNode: _availabilityNodes[availabilities[i].index],
          onSelect: () => _selectAvailability(availabilities[i]),
          onNavigateLeft: i > 0
              ? _availabilityNodes[availabilities[i - 1].index].requestFocus
              : _tabNodes[tabs.last.index].requestFocus,
          onNavigateRight: i < availabilities.length - 1
              ? _availabilityNodes[availabilities[i + 1].index].requestFocus
              : null,
          onNavigateDown: down,
          onNavigateUp: upFromFilters,
          onBack: back,
        ),
      ],
    ];
    final gap = (stage ? 24 * ockerScale(context) : 16).toDouble();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        mainAxisSize: .min,
        children: [
          TabChipStrip(children: kindChips),
          if (availabilityChips.isNotEmpty) ...[SizedBox(width: gap), TabChipStrip(children: availabilityChips)],
        ],
      ),
    );
  }

  Widget _buildStage() {
    return OverlaySheetHost(
      canPop: false,
      onSystemBack: () {
        if (BackKeyCoordinator.consumeIfHandled()) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        body: CatalogPersonStage(
          key: _stageKey,
          name: _person?.name ?? widget.name,
          portraitUrl: _person?.thumbUrl ?? widget.thumbUrl,
          departmentsLine: _departmentsLine(),
          lifeLine: _lifeLine(),
          roleLine: _roleLine(),
          summary: _person?.summary,
          facts: _facts(),
          filters: _filters(stage: true),
          grids: _loading ? const [] : _gridSlivers(stage: true),
          scrollController: _stageScroll,
          loading: _loading,
          emptyMessage: t.discover.noContentAvailable,
          biographyLabel: t.actor.biography,
          onOpenBiography: _openBiography,
          onFocusFilters: _focusFilters,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- page

  @override
  void navigateToAppBar() {
    // The page's app bar holds nothing; UP out of the titles reaches the tabs.
    if (!_loading && (_owned.isNotEmpty || _others.isNotEmpty)) {
      _focusFilters();
    } else {
      super.navigateToAppBar();
    }
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final tk = tokens(context);
    final isTv = PlatformDetector.isTV();
    final avatar = isTv ? 120.0 : 96.0;
    final lifeLine = _lifeLine();
    final roleLine = _roleLine();
    final summary = _person?.summary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Row(
            children: [
              ClipOval(
                child: OptimizedMediaImage(
                  client: null,
                  imagePath: _person?.thumbUrl ?? widget.thumbUrl,
                  width: avatar,
                  height: avatar,
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
                      _person?.name ?? widget.name,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: .bold),
                      maxLines: 2,
                      overflow: .ellipsis,
                    ),
                    if (lifeLine != null) ...[
                      const SizedBox(height: 4),
                      Text(lifeLine, style: theme.textTheme.bodySmall?.copyWith(color: tk.textMuted)),
                    ],
                    if (roleLine != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        roleLine,
                        style: theme.textTheme.bodyMedium?.copyWith(color: tk.accent, fontWeight: .w600),
                        maxLines: 1,
                        overflow: .ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (summary != null) ...[
            const SizedBox(height: 12),
            CollapsibleText(
              text: summary,
              maxLines: isTv ? 3 : 4,
              style: theme.textTheme.bodyMedium?.copyWith(color: tk.textMuted),
              skipTraversal: false,
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    final style = Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: .bold, fontSize: PlatformDetector.isTV() ? 28 : null);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(text, style: style),
      ),
    );
  }

  List<Widget> _buildSections() {
    if (_loading) return [LoadingIndicatorBox.sliver];
    if (_owned.isEmpty && _others.isEmpty) {
      return [SliverEmptyState(message: t.discover.noContentAvailable, icon: Symbols.person_rounded)];
    }
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
          child: Align(alignment: Alignment.centerLeft, child: _filters(stage: false)),
        ),
      ),
      ..._gridSlivers(stage: false),
    ];
  }

  void _replaceItem(MediaItem updated) {
    final index = _owned.indexWhere((title) => title.item.globalKey == updated.globalKey);
    if (index < 0) return;
    setState(() => _owned = [..._owned]..[index] = (item: updated, credit: _owned[index].credit));
  }

  @override
  Widget build(BuildContext context) {
    if (_usesStage(context)) return _buildStage();
    return buildDetailScaffold(
      slivers: [
        CustomAppBar(title: Text(_person?.name ?? widget.name), pinned: true, actions: buildFocusableAppBarActions()),
        SliverToBoxAdapter(child: _buildHeader()),
        ..._buildSections(),
      ],
    );
  }
}

/// [owned] — the person's titles on the viewer's servers — and [credits] —
/// their Discover filmography — as the two sections of their page: the
/// library titles, one entry per title however many servers hold it, newest
/// first, each with the credit it answers for; and the credits none of them
/// answers for, newest first with guest appearances after the work proper.
///
/// A Plex copy names its Discover entry in its guid, so it is matched by id;
/// other servers carry no Discover id and are matched by kind, title (or
/// original title) and a year that may be one out.
@visibleForTesting
({List<PersonOwnedTitle> owned, List<CatalogPersonCredit> others}) splitPersonTitles({
  required List<MediaItem> owned,
  required List<CatalogPersonCredit> credits,
}) {
  CatalogPersonCredit? creditFor(MediaItem copy) {
    final guid = copy.guid;
    if (guid != null && guid.startsWith('plex://')) {
      final tail = guid.substring(guid.lastIndexOf('/') + 1);
      final byId = credits.firstWhereOrNull((credit) => credit.item.ids.plex == tail);
      if (byId != null) return byId;
    }
    final titles = {_titleKey(copy.title), _titleKey(copy.originalTitle)}..remove('');
    return credits.firstWhereOrNull(
      (credit) =>
          credit.item.kind == copy.kind &&
          titles.contains(_titleKey(credit.item.title)) &&
          _yearsAgree(credit.item.year, copy.year),
    );
  }

  final matched = <String>{};
  final seen = <String>{};
  final ownedTitles = <PersonOwnedTitle>[];
  for (final copy in owned) {
    if (copy.kind != MediaKind.movie && copy.kind != MediaKind.show) continue;
    final credit = creditFor(copy);
    if (credit != null) matched.add(credit.item.identityKey);
    final key = credit?.item.identityKey ?? '${copy.kind.id}|${_titleKey(copy.title)}|${copy.year ?? 0}';
    if (seen.add(key)) ownedTitles.add((item: copy, credit: credit));
  }
  // Stable, so titles of one year keep the order the servers sent them in.
  mergeSort(ownedTitles, compare: (a, b) => (b.item.year ?? 0).compareTo(a.item.year ?? 0));

  final others = [
    for (final credit in credits)
      if (!matched.contains(credit.item.identityKey)) credit,
  ];
  List<CatalogPersonCredit> newestFirst(Iterable<CatalogPersonCredit> credits) {
    final list = credits.toList();
    mergeSort(list, compare: (a, b) => (b.item.year ?? 0).compareTo(a.item.year ?? 0));
    return list;
  }

  return (
    owned: ownedTitles,
    others: [
      ...newestFirst(others.where((credit) => !credit.isAppearance)),
      ...newestFirst(others.where((credit) => credit.isAppearance)),
    ],
  );
}

String _titleKey(String? title) => (title ?? '').toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// Release and library years disagree across new-year boundaries; a missing
/// year on either side says nothing against the match.
bool _yearsAgree(int? a, int? b) => a == null || b == null || (a - b).abs() <= 1;
