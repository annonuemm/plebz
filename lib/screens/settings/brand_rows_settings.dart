import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/dpad_reorder_mixin.dart';
import '../../focus/input_mode_tracker.dart';
import '../../i18n/strings.g.dart';
import '../../services/brand_rows_service.dart' show brandRowsLayout;
import '../../services/settings_service.dart' hide ThemeMode;
import '../../services/streaming_brands.dart';
import '../../utils/dialogs.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/management_list.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_builder.dart';
import 'settings_utils.dart';

/// The home screen's brand rows in Darstellung → Startseite (Plebz): the
/// switch, and — only while it is on — which services and where.
List<Widget> brandRowsSettingsRows() => [
  SettingSwitchTile(
    pref: PlebzPrefs.showBrandRows,
    icon: Symbols.subscriptions_rounded,
    title: t.settings.showBrandRows,
    subtitle: t.settings.showBrandRowsDescription,
  ),
  SettingValueBuilder<bool>(
    pref: PlebzPrefs.showBrandRows,
    builder: (context, on, _) => on
        ? Column(
            mainAxisSize: .min,
            children: [
              SettingValueBuilder<String>(
                pref: PlebzPrefs.brandRowsLayout,
                builder: (context, stored, _) => SettingNavigationTile(
                  icon: Symbols.tune_rounded,
                  title: t.settings.brandRowsPick,
                  subtitle: BrandRowsLayout.decode(stored).visible.map((brand) => brand.displayName).join(', '),
                  onTap: () => unawaited(showBrandRowsManagementSheet(context)),
                ),
              ),
              SettingSelectionTile<BrandRowsPosition>(
                pref: PlebzPrefs.brandRowsPosition,
                icon: Symbols.swap_vert_rounded,
                title: t.settings.brandRowsPosition,
                subtitleBuilder: _positionLabel,
                options: [
                  for (final position in BrandRowsPosition.values)
                    DialogOption(value: position, title: _positionLabel(position)),
                ],
              ),
            ],
          )
        : const SizedBox.shrink(),
  ),
];

String _positionLabel(BrandRowsPosition position) => switch (position) {
  BrandRowsPosition.top => t.settings.brandRowsPositionTop,
  BrandRowsPosition.afterRecommendations => t.settings.brandRowsPositionAfterRecommendations,
  BrandRowsPosition.bottom => t.settings.brandRowsPositionBottom,
};

/// "Anbieter auswählen": which services get a row and in which order,
/// arranged the way "Ligen verwalten" arranges the Sport page — a dialog on a
/// television, a sheet elsewhere.
Future<void> showBrandRowsManagementSheet(BuildContext context) {
  if (PlatformDetector.isTV()) {
    return showScopedDialog<void>(
      context: context,
      builder: (context) => const BrandRowsManagementList(isDialog: true),
    );
  }
  return OverlaySheetController.showAdaptive<void>(
    context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const BrandRowsManagementList(isDialog: false),
  );
}

class BrandRowsManagementList extends StatefulWidget {
  const BrandRowsManagementList({super.key, required this.isDialog});

  final bool isDialog;

  @override
  State<BrandRowsManagementList> createState() => _BrandRowsManagementListState();
}

class _BrandRowsManagementListState extends State<BrandRowsManagementList>
    with DpadReorderListMixin<StreamingBrand, BrandRowsManagementList> {
  final _listFocusNode = FocusNode(debugLabel: 'brand_rows_management');
  final _scrollController = ScrollController();
  late List<StreamingBrand> _brands = [...brandRowsLayout().order];

  @override
  List<StreamingBrand> get reorderItems => _brands;

  @override
  set reorderItems(List<StreamingBrand> value) => _brands = value;

  @override
  int get lastReorderColumn => 1;

  @override
  ScrollController? get reorderScrollController => _scrollController;

  @override
  void onReorderMoveConfirmed() => _persistOrder();

  @override
  void onReorderColumnActivated(int column, int index) {
    if (column == 1) _toggleHidden(_brands[index]);
  }

  @override
  void dispose() {
    _listFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _write(BrandRowsLayout layout) =>
      SettingsService.instance.write(PlebzPrefs.brandRowsLayout, layout.encode());

  void _persistOrder() => unawaited(_write(brandRowsLayout().withOrder(_brands)));

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final brand = _brands.removeAt(oldIndex);
      _brands.insert(newIndex, brand);
    });
    _persistOrder();
  }

  /// The last service on show stays: switching the rows off is the switch's job.
  void _toggleHidden(StreamingBrand brand) {
    final layout = brandRowsLayout();
    unawaited(_write(layout.withHidden(brand, !layout.isHidden(brand))));
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardMode = InputModeTracker.isKeyboardMode(context);
    return SettingValueBuilder<String>(
      pref: PlebzPrefs.brandRowsLayout,
      builder: (context, stored, _) {
        final layout = BrandRowsLayout.decode(stored);
        return ManagementScaffold(
          isDialog: widget.isDialog,
          title: t.settings.brandRowsPick,
          icon: Symbols.tune_rounded,
          listFocusNode: _listFocusNode,
          onKeyEvent: handleReorderKeyEvent,
          child: ReorderableListView.builder(
            scrollController: _scrollController,
            shrinkWrap: !widget.isDialog,
            onReorderItem: _reorder,
            itemCount: _brands.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            buildDefaultDragHandles: false,
            itemBuilder: (context, index) {
              final brand = _brands[index];
              final isFocused = isKeyboardMode && index == focusedIndex;
              return ManagementTile(
                key: ValueKey(brand),
                index: index,
                title: brand.displayName,
                subtitle: null,
                leadingIcon: Symbols.subscriptions_rounded,
                isHidden: layout.isHidden(brand),
                isFocused: isFocused,
                isMoving: index == movingIndex,
                focusedColumn: isFocused ? focusedColumn : null,
                showTooltip: t.settings.brandRowsShow,
                hideTooltip: t.settings.brandRowsHide,
                onToggleHidden: () => _toggleHidden(brand),
              );
            },
          ),
        );
      },
    );
  }
}
