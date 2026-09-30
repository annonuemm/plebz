import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/trailer_stage_selection.dart';
import '../../media/year_filter.dart';
import '../../providers/libraries_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/plex_client.dart';
import '../../services/trailer_stage_queue.dart';
import '../../utils/app_logger.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/loading_indicator_box.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';
import 'trailer_stage_screen.dart';

/// "What are you in the mood for today?" — asked once per run of the app.
///
/// Three questions, each of which may be left open, and an open question is
/// the default. Somebody who wants to be surprised presses Start and gets
/// their whole collection in random order.
class TrailerStageSetupScreen extends StatefulWidget {
  const TrailerStageSetupScreen({super.key});

  @override
  State<TrailerStageSetupScreen> createState() => _TrailerStageSetupScreenState();
}

class _TrailerStageSetupScreenState extends State<TrailerStageSetupScreen> {
  TrailerStageSelection _selection = TrailerStageSession.selection ?? const TrailerStageSelection();

  /// The libraries the stage may draw from. Resolved in [initState] without a
  /// single request, so the questions are on the television at once.
  late final List<TrailerStageLibrary> _libraries = trailerStageLibrariesFrom(
    libraries: context.read<LibrariesProvider>().libraries,
    clientFor: context.read<MultiServerProvider>().getClientForServer,
  );

  /// The same libraries with their genre catalogs, which cost two requests
  /// each. Loaded behind the drawn screen; until it arrives the genre row says
  /// so, and every other question is already answerable.
  List<TrailerStageLibrary>? _withGenres;
  bool _genresFailed = false;

  static int get _maxYear => DateTime.now().year + 1;

  @override
  void initState() {
    super.initState();
    // A selection already given this run is not asked for again — that is what
    // "once per start" means. The questions come back on the next start, or
    // when the stage's own "choose again" clears them. Genres do not have to
    // be loaded for that: they were loaded when they were chosen.
    if (_libraries.isNotEmpty && TrailerStageSession.selection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start(_libraries);
      });
      return;
    }
    _loadGenres().catchError((Object error) {
      appLogger.w('Trailer stage: genres could not be resolved', error: error);
      if (mounted) setState(() => _genresFailed = true);
    });
  }

  Future<void> _loadGenres() async {
    final resolved = await withTrailerStageGenres(
      _libraries,
      loadFilterValues: (client, filter) async {
        // Plex answers its filter categories without values; Jellyfin sends
        // both at once and never reaches this.
        if (client is PlexClient) return client.getFilterValues(filter.key);
        return const [];
      },
    );
    if (!mounted) return;
    setState(() => _withGenres = resolved);
  }

  /// Every genre any eligible library knows, once, in alphabetical order.
  List<String> get _genreOptions {
    final kinds = _selection.kind;
    final names = <String>{};
    for (final library in _withGenres ?? const <TrailerStageLibrary>[]) {
      if (!kinds.accepts(library.kind)) continue;
      names.addAll(library.genres.keys);
    }
    final sorted = names.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  String get _kindLabel => switch (_selection.kind) {
    TrailerStageKind.any => t.trailerStage.kindAny,
    TrailerStageKind.movie => t.trailerStage.kindMovie,
    TrailerStageKind.show => t.trailerStage.kindShow,
  };

  String get _genreLabel =>
      _selection.genres.isEmpty ? t.trailerStage.anything : (_selection.genres.toList()..sort()).join(', ');

  String _yearLabel(int? year) => year?.toString() ?? t.trailerStage.anything;

  Future<void> _pickKind() async {
    final chosen = await showOptionPickerDialog<TrailerStageKind>(
      context,
      title: t.trailerStage.kind,
      options: [
        (icon: Symbols.done_all_rounded, label: t.trailerStage.kindAny, value: TrailerStageKind.any),
        (icon: Symbols.movie_rounded, label: t.trailerStage.kindMovie, value: TrailerStageKind.movie),
        (icon: Symbols.live_tv_rounded, label: t.trailerStage.kindShow, value: TrailerStageKind.show),
      ],
    );
    if (chosen == null || !mounted) return;
    setState(() {
      // Genres belong to the kind that offered them: a series genre left over
      // from the previous answer would quietly filter every film away.
      final stillOffered = _selection.genres.where((genre) {
        for (final library in _withGenres ?? const <TrailerStageLibrary>[]) {
          if (chosen.accepts(library.kind) && library.genres.containsKey(genre)) return true;
        }
        return false;
      }).toSet();
      _selection = _selection.copyWith(kind: chosen, genres: stillOffered);
    });
  }

  Future<void> _pickGenres() async {
    final options = _genreOptions;
    if (options.isEmpty) return;
    final chosen = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute<Set<String>>(
        builder: (_) => _GenrePickerScreen(options: options, initial: _selection.genres),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _selection = _selection.copyWith(genres: chosen));
  }

  Future<void> _editYear({required bool isFrom}) async {
    final current = isFrom ? _selection.years.from : _selection.years.to;
    final label = isFrom ? t.trailerStage.yearFrom : t.trailerStage.yearTo;
    final entered = await showTextInputDialog(
      context,
      title: label,
      labelText: label,
      initialValue: current?.toString() ?? '',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
      // Empty is a valid answer — it is how an end is left open.
      allowEmpty: true,
      validator: (value) {
        if (value.trim().isEmpty) return null;
        final year = int.tryParse(value.trim());
        if (year == null || year < 1900 || year > _maxYear) return t.settings.yearFilterInvalid(max: _maxYear);
        return null;
      },
    );
    if (entered == null || !mounted) return;
    final year = int.tryParse(entered.trim()) ?? 0;
    final years = _selection.years;
    setState(() {
      _selection = _selection.copyWith(
        years: yearRangeFrom(isFrom ? year : years.from ?? 0, isFrom ? years.to ?? 0 : year),
      );
    });
  }

  void _start(List<TrailerStageLibrary> libraries) {
    if (libraries.isEmpty) return;
    TrailerStageSession.remember(_selection);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TrailerStageScreen(libraries: libraries, selection: _selection),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final genreOptions = _genreOptions;
    final genresPending = _withGenres == null && !_genresFailed;
    return SettingsPage(
      title: Text(t.trailerStage.title),
      children: [
        if (_libraries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(t.trailerStage.noLibraries, style: theme.textTheme.bodyLarge),
          )
        else ...[
          SettingsGroup(
            title: t.trailerStage.mood,
            children: [
              FocusableListTile(
                autofocus: true,
                leading: const AppIcon(Symbols.theaters_rounded, fill: 1),
                title: Text(t.trailerStage.kind),
                trailing: Text(_kindLabel, style: theme.textTheme.bodyMedium),
                onTap: _pickKind,
              ),
              FocusableListTile(
                leading: const AppIcon(Symbols.category_rounded, fill: 1),
                title: Text(t.trailerStage.genres),
                subtitle: Text(genresPending ? t.trailerStage.genresLoading : _genreLabel),
                trailing: genresPending ? const LoadingIndicatorBox() : null,
                enabled: genreOptions.isNotEmpty,
                onTap: genreOptions.isEmpty ? null : _pickGenres,
              ),
              FocusableListTile(
                leading: const AppIcon(Symbols.calendar_month_rounded, fill: 1),
                title: Text(t.trailerStage.yearFrom),
                trailing: Text(_yearLabel(_selection.years.from), style: theme.textTheme.bodyMedium),
                onTap: () => _editYear(isFrom: true),
              ),
              FocusableListTile(
                leading: const SizedBox(width: 24),
                title: Text(t.trailerStage.yearTo),
                trailing: Text(_yearLabel(_selection.years.to), style: theme.textTheme.bodyMedium),
                onTap: () => _editYear(isFrom: false),
              ),
            ],
          ),
          SettingsGroup(
            children: [
              FocusableListTile(
                leading: const AppIcon(Symbols.play_arrow_rounded, fill: 1),
                title: Text(t.trailerStage.start),
                subtitle: Text(_selection.isWideOpen ? t.trailerStage.startAnything : t.trailerStage.startNarrowed),
                onTap: () => _start(_withGenres ?? _libraries),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The genres, one per row, with "anything" as the way back out of a choice.
class _GenrePickerScreen extends StatefulWidget {
  const _GenrePickerScreen({required this.options, required this.initial});

  final List<String> options;
  final Set<String> initial;

  @override
  State<_GenrePickerScreen> createState() => _GenrePickerScreenState();
}

class _GenrePickerScreenState extends State<_GenrePickerScreen> {
  late final Set<String> _chosen = {...widget.initial};

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: Text(t.trailerStage.genres),
    onBackPressed: () => Navigator.of(context).pop(_chosen),
    children: [
      SettingsGroup(
        children: [
          FocusableListTile(
            autofocus: _chosen.isEmpty,
            leading: const AppIcon(Symbols.done_all_rounded, fill: 1),
            title: Text(t.trailerStage.anything),
            selected: _chosen.isEmpty,
            onTap: () => setState(_chosen.clear),
          ),
          for (final genre in widget.options)
            FocusableListTile(
              autofocus: _chosen.isNotEmpty && genre == widget.options.firstWhere(_chosen.contains, orElse: () => ''),
              title: Text(genre),
              selected: _chosen.contains(genre),
              trailing: _chosen.contains(genre) ? const AppIcon(Symbols.check_rounded, fill: 1) : null,
              onTap: () => setState(() => _chosen.contains(genre) ? _chosen.remove(genre) : _chosen.add(genre)),
            ),
        ],
      ),
    ],
  );
}
