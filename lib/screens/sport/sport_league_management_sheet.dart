import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/dpad_reorder_mixin.dart';
import '../../focus/input_mode_tracker.dart';
import '../../i18n/strings.g.dart';
import '../../services/settings_service.dart';
import '../../services/sport/sport_league_names.dart';
import '../../services/sport/sport_models.dart';
import '../../utils/dialogs.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/management_list.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/settings_builder.dart';

/// "Ligen verwalten" (Plebz): which competitions the Sport page shows and in
/// which order, arranged the way "Sender verwalten" arranges the guide's
/// groups — a dialog on a television, a sheet elsewhere.
Future<void> showSportLeagueManagementSheet(BuildContext context) {
  if (PlatformDetector.isTV()) {
    return showScopedDialog<void>(
      context: context,
      builder: (context) => const SportLeagueManagementList(isDialog: true),
    );
  }
  return OverlaySheetController.showAdaptive<void>(
    context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const SportLeagueManagementList(isDialog: false),
  );
}

class SportLeagueManagementList extends StatefulWidget {
  const SportLeagueManagementList({super.key, required this.isDialog});

  final bool isDialog;

  @override
  State<SportLeagueManagementList> createState() => _SportLeagueManagementListState();
}

class _SportLeagueManagementListState extends State<SportLeagueManagementList>
    with DpadReorderListMixin<SportLeague, SportLeagueManagementList> {
  final _listFocusNode = FocusNode(debugLabel: 'sport_league_management');
  final _scrollController = ScrollController();
  late List<SportLeague> _leagues = [...sportLeagueLayout().order];

  @override
  List<SportLeague> get reorderItems => _leagues;

  @override
  set reorderItems(List<SportLeague> value) => _leagues = value;

  @override
  int get lastReorderColumn => 1;

  @override
  ScrollController? get reorderScrollController => _scrollController;

  @override
  void onReorderMoveConfirmed() => _persistOrder();

  @override
  void onReorderColumnActivated(int column, int index) {
    if (column == 1) _toggleHidden(_leagues[index]);
  }

  @override
  void dispose() {
    _listFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _write(SportLeagueLayout layout) =>
      SettingsService.instance.write(PlebzPrefs.sportLeagueLayout, layout.encode());

  void _persistOrder() => unawaited(_write(sportLeagueLayout().withOrder(_leagues)));

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final league = _leagues.removeAt(oldIndex);
      _leagues.insert(newIndex, league);
    });
    _persistOrder();
  }

  /// The last competition on show stays: the page has nothing else to show.
  void _toggleHidden(SportLeague league) {
    final layout = sportLeagueLayout();
    unawaited(_write(layout.withHidden(league, !layout.isHidden(league))));
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardMode = InputModeTracker.isKeyboardMode(context);
    return SettingValueBuilder<String>(
      pref: PlebzPrefs.sportLeagueLayout,
      builder: (context, stored, _) {
        final layout = SportLeagueLayout.decode(stored);
        return ManagementScaffold(
          isDialog: widget.isDialog,
          title: t.sport.manageLeagues,
          icon: Symbols.tune_rounded,
          listFocusNode: _listFocusNode,
          onKeyEvent: handleReorderKeyEvent,
          child: ReorderableListView.builder(
            scrollController: _scrollController,
            shrinkWrap: !widget.isDialog,
            onReorderItem: _reorder,
            itemCount: _leagues.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            buildDefaultDragHandles: false,
            itemBuilder: (context, index) {
              final league = _leagues[index];
              final isFocused = isKeyboardMode && index == focusedIndex;
              return ManagementTile(
                key: ValueKey(league),
                index: index,
                title: sportLeagueName(league),
                subtitle: league == SportLeague.europaLeague ? t.sport.europaLeagueLate : null,
                leadingIcon: league.isDomestic ? Symbols.sports_soccer_rounded : Symbols.emoji_events_rounded,
                isHidden: layout.isHidden(league),
                isFocused: isFocused,
                isMoving: index == movingIndex,
                focusedColumn: isFocused ? focusedColumn : null,
                showTooltip: t.sport.showLeague,
                hideTooltip: t.sport.hideLeague,
                onToggleHidden: () => _toggleHidden(league),
              );
            },
          ),
        );
      },
    );
  }
}
