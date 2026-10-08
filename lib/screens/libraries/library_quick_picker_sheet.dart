import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_library.dart';
import '../../focus/input_mode_tracker.dart';
import '../../redesign/ocker_skin.dart';
import '../../redesign/ocker_type.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/content_utils.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/overlay_sheet.dart';
import 'library_server_label.dart';

class LibraryQuickPickerSheet extends StatefulWidget {
  final List<MediaLibrary> libraries;
  final String? selectedLibraryKey;
  final bool isLoading;
  final bool groupByServer;
  final String emptyMessage;
  final ValueChanged<String> onSelected;

  const LibraryQuickPickerSheet({
    super.key,
    required this.libraries,
    required this.selectedLibraryKey,
    required this.isLoading,
    required this.groupByServer,
    required this.emptyMessage,
    required this.onSelected,
  });

  @override
  State<LibraryQuickPickerSheet> createState() => _LibraryQuickPickerSheetState();
}

class _LibraryQuickPickerSheetState extends State<LibraryQuickPickerSheet> {
  /// Carried by the library being browsed, so the sheet opens on it instead of
  /// at the top of the list. Handed to the host as well: the host focuses the
  /// first thing it can traverse to unless it is told which node to use.
  final _selectedFocusNode = FocusNode(debugLabel: 'LibraryQuickPickerSelected');

  List<MediaLibrary> get libraries => widget.libraries;
  String? get selectedLibraryKey => widget.selectedLibraryKey;
  bool get isLoading => widget.isLoading;
  bool get groupByServer => widget.groupByServer;
  String get emptyMessage => widget.emptyMessage;
  ValueChanged<String> get onSelected => widget.onSelected;

  bool _claimedInitialFocus = false;

  /// Claim the opening focus for the library being browsed, once its row
  /// exists.
  ///
  /// Driven from `build` rather than `initState` because the sheet is opened
  /// before its list is: a cold start draws it loading and empty, and a node
  /// that is attached to nothing is one the host will rightly ignore.
  void _claimInitialFocus() {
    if (_claimedInitialFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _claimedInitialFocus || _selectedFocusNode.context == null) return;
      _claimedInitialFocus = true;
      OverlaySheetController.maybeOf(context)?.adoptInitialFocusNode(_selectedFocusNode);
      if (InputModeTracker.isKeyboardMode(context, listen: false)) _selectedFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _selectedFocusNode.dispose();
    super.dispose();
  }

  List<Widget> _buildLibraryRows(BuildContext context) {
    final ocker = isOcker(context);
    final scale = ockerScale(context);
    return buildLibraryServerEntries<Widget>(
      libraries,
      groupByServer: groupByServer,
      buildHeader: (library, fallbackServerName) => Padding(
        padding: ocker
            ? EdgeInsets.fromLTRB(26 * scale, 26 * scale, 26 * scale, 10 * scale)
            : const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: LibraryServerLabel(
          library: library,
          fallbackServerName: fallbackServerName,
          badgeSize: ocker ? 13 * scale : 12,
          // The name of a server is a label, and in this design a label is set
          // in mono — the same style the group bar gives the source at the
          // left of each of its rows, because this is the same thing said in a
          // sheet instead of on a bar.
          style: ocker
              ? OckerType.of(context).sourceLabel.copyWith(color: tokens(context).ink(0.45))
              : libraryServerHeaderStyle(context),
          uppercase: ocker,
          constrainText: true,
        ),
      ),
      buildItem: (library, {required bool showServerName}) =>
          _buildLibraryTile(context, library, showServerName: showServerName),
    );
  }

  Widget _buildLibraryTile(BuildContext context, MediaLibrary library, {required bool showServerName}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = library.globalKey == selectedLibraryKey;
    if (isOcker(context)) {
      return _buildOckerLibraryTile(context, library, showServerName: showServerName, isSelected: isSelected);
    }
    final foregroundColor = isSelected ? colorScheme.primary : null;

    return FocusableListTile(
      key: ValueKey('library_quick_picker_${library.globalKey}'),
      dense: false,
      visualDensity: VisualDensity.standard,
      selected: isSelected,
      // The cursor opens on the library being browsed, not at the top of the
      // list: the sheet asks "which one", and the answer it already has is
      // where the remote should start. Only where there is a cursor at all —
      // a focus ring on a touch screen is noise.
      focusNode: isSelected ? _selectedFocusNode : null,
      autofocus: isSelected && InputModeTracker.isKeyboardMode(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: AppIcon(ContentTypeHelper.getLibraryIcon(library.kind.id), fill: 1, size: 22, color: foregroundColor),
      title: Text(
        library.title,
        maxLines: 1,
        overflow: .ellipsis,
        style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: foregroundColor),
      ),
      subtitle: showServerName
          ? LibraryServerLabel(
              library: library,
              badgeSize: 10,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
              ),
              constrainText: true,
            )
          : null,
      trailing: isSelected ? AppIcon(Symbols.check_rounded, fill: 1, color: colorScheme.primary) : null,
      onTap: () => onSelected(library.globalKey),
    );
  }

  /// The same row in the redesign's own language.
  ///
  /// Three things go and one arrives. The glyph goes: `sectionIcons` is off in
  /// this design for the reason the whole navigation was rebuilt around — at
  /// television distance a word is read and an outline symbol is guessed — and
  /// a list of libraries is nothing but words. The tick goes, and so does the
  /// bold: one state had two marks, and neither of them was the accent, whose
  /// three jobs include saying which one is active. What arrives is the mark
  /// the header already uses for exactly this — a 2 px accent rule under the
  /// name. Transparent when it is not the one, so the rows cannot change
  /// height as the choice moves.
  Widget _buildOckerLibraryTile(
    BuildContext context,
    MediaLibrary library, {
    required bool showServerName,
    required bool isSelected,
  }) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    final scale = ockerScale(context);
    // Under glass the chosen library is a pane washed with the accent, as in
    // every glass menu; a rule under it as well would mark it twice.
    final ruled = !ockerGlass(context);

    return FocusableListTile(
      key: ValueKey('library_quick_picker_${library.globalKey}'),
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
      selected: isSelected,
      focusNode: isSelected ? _selectedFocusNode : null,
      autofocus: isSelected && InputModeTracker.isKeyboardMode(context),
      contentPadding: EdgeInsets.symmetric(horizontal: 26 * scale, vertical: 6 * scale),
      title: Align(
        alignment: .centerLeft,
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              Text(
                library.title,
                maxLines: 1,
                overflow: .ellipsis,
                // A library is a group entry — the style is named for it, and
                // the group bar this sheet replaced is where these lived.
                style: type.groupEntry(active: isSelected).copyWith(color: tk.ink(isSelected ? 1 : 0.72)),
              ),
              if (ruled) ...[
                SizedBox(height: 4.5 * scale),
                Container(height: 2 * scale, color: isSelected ? tk.accent : Colors.transparent),
              ],
            ],
          ),
        ),
      ),
      subtitle: showServerName
          ? Padding(
              padding: EdgeInsets.only(top: 6 * scale),
              child: LibraryServerLabel(
                library: library,
                badgeSize: 11 * scale,
                style: type.sourceLabel.copyWith(color: tk.ink(0.45)),
                uppercase: true,
                constrainText: true,
              ),
            )
          : null,
      onTap: () => onSelected(library.globalKey),
    );
  }

  /// What this sheet is. Under the redesign a line that *names* something is
  /// mono, uppercase and spaced — the same style as the heading over every
  /// shelf on the home page — and it is closed by the hairline that does the
  /// separating everywhere else instead of a box.
  Widget _buildHeading(BuildContext context, ThemeData theme) {
    if (!isOcker(context)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Align(
          alignment: .centerLeft,
          child: Text(t.libraries.selectLibrary, style: theme.textTheme.titleMedium),
        ),
      );
    }

    final tk = tokens(context);
    final scale = ockerScale(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(26 * scale, 24 * scale, 26 * scale, 0),
      child: Column(
        crossAxisAlignment: .start,
        mainAxisSize: .min,
        children: [
          Text(
            OckerType.of(context).headingCase(t.libraries.selectLibrary),
            style: OckerType.of(context).sectionHeading.copyWith(color: tk.ink(0.45)),
          ),
          SizedBox(height: 14 * scale),
          Container(height: 1, color: tk.ink(0.12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _claimInitialFocus();

    return Column(
      mainAxisSize: .min,
      children: [
        _buildHeading(context, theme),
        if (isLoading && libraries.isEmpty)
          const Padding(padding: .symmetric(vertical: 32), child: CircularProgressIndicator())
        else if (libraries.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Text(emptyMessage, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          )
        else
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: _buildLibraryRows(context),
            ),
          ),
      ],
    );
  }
}
