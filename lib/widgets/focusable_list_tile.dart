import 'package:flutter/material.dart';
import '../focus/input_mode_tracker.dart';
import '../focus/focus_theme.dart';
import '../theme/mono_tokens.dart';
import '../redesign/ocker_skin.dart';
import '../focus/focusable_tile_mixin.dart';
import '../utils/platform_detector.dart';
import 'clickable_cursor.dart';

/// A ListTile that accepts a FocusNode for keyboard/controller navigation.
///
/// Uses Flutter's native ListTile focus support - no custom styling wrapper.
/// The focusNode allows programmatic focus control (e.g., auto-focus first item).
class FocusableListTile extends StatefulWidget {
  final Widget? title;

  final Widget? subtitle;

  final Widget? leading;

  final Widget? trailing;

  final VoidCallback? onTap;

  final VoidCallback? onLongPress;

  final bool dense;

  final bool enabled;

  final bool selected;

  /// Optional FocusNode for keyboard/controller navigation.
  final FocusNode? focusNode;

  final bool autofocus;

  final EdgeInsetsGeometry? contentPadding;

  final VisualDensity? visualDensity;

  final double? horizontalTitleGap;

  final double? minLeadingWidth;

  /// Under "Redesign – Glas", mark focus and the chosen row with panes of
  /// glass behind the row — bright for focus, a quiet one washed with the
  /// accent for the chosen — instead of the ring. Asked for per list, where
  /// the list stands on glass; a hosted sheet under glass asks for every row
  /// in it ([OckerOnGlass]).
  final bool glassMarks;

  const FocusableListTile({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.dense = true,
    this.enabled = true,
    this.selected = false,
    this.focusNode,
    this.autofocus = false,
    this.contentPadding,
    this.visualDensity = const VisualDensity(vertical: -3),
    this.horizontalTitleGap,
    this.minLeadingWidth,
    this.glassMarks = false,
  });

  @override
  State<FocusableListTile> createState() => _FocusableListTileState();
}

class _FocusableListTileState extends State<FocusableListTile> with FocusableTileStateMixin<FocusableListTile> {
  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  Widget build(BuildContext context) {
    final automotive = PlatformDetector.isAutomotive();
    // "Ocker" marks focus with a hairline ring on the row's own edge, not with
    // the pale filled plate Material puts under a focused ListTile. These rows
    // are half the app's menus — the library picker, every settings list,
    // every chooser — and the plate was the last place the old focus language
    // survived at that scale.
    final ocker = isOcker(context);
    final showFocus = ocker && isTileFocused && InputModeTracker.isKeyboardMode(context);

    Widget tile = ListTile(
      title: widget.title,
      subtitle: widget.subtitle,
      leading: widget.leading,
      trailing: widget.trailing,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      dense: automotive ? false : widget.dense,
      enabled: widget.enabled,
      selected: widget.selected,
      contentPadding: widget.contentPadding,
      visualDensity: automotive ? VisualDensity.standard : widget.visualDensity,
      focusNode: effectiveFocusNode,
      autofocus: widget.autofocus,
      horizontalTitleGap: widget.horizontalTitleGap,
      minLeadingWidth: widget.minLeadingWidth,
      // Transparent, not absent: the plate is what the ring replaces, and
      // leaving both would be two marks for one state.
      focusColor: ocker ? Colors.transparent : null,
    );

    if (ocker) {
      tile = _ockerRowMark(
        context,
        tile,
        showFocus: showFocus,
        selected: widget.selected,
        glassMarks: widget.glassMarks,
      );
    }

    return MouseRegion(
      cursor: widget.enabled && (widget.onTap != null || widget.onLongPress != null)
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: tile,
    );
  }
}

/// How a row marks focus under the redesign, for every kind of row: panes of
/// glass behind it where the list stands on glass, the hairline ring on the
/// row's own edge elsewhere.
///
/// One function for plain, switch and checkbox rows alike. The switch and
/// checkbox rows kept Material's pale plate long after the plain rows lost it,
/// and a settings page is mostly those.
Widget _ockerRowMark(
  BuildContext context,
  Widget tile, {
  required bool showFocus,
  bool selected = false,
  bool glassMarks = false,
}) {
  if ((glassMarks || OckerOnGlass.appliesAt(context)) && ockerGlass(context)) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: showFocus || selected ? 1 : 0,
              duration: ockerInkFade(context),
              curve: Curves.easeOutCubic,
              child: OckerGlassFocusFill(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens(context).radiusSm)),
                bright: showFocus,
                tint: selected ? 1 : 0,
              ),
            ),
          ),
        ),
        tile,
      ],
    );
  }
  return DecoratedBox(
    position: DecorationPosition.foreground,
    // Drawn inside, unlike everywhere else in this design: a row runs the
    // full width of what holds it, so a ring outside its edge would sit on
    // the row above and the row below.
    //
    // In the shape of the card the row fills, where it fills one: a ring
    // with a smaller corner is cut off by the card's clip, and what was
    // left of it was four lines with gaps at every corner.
    decoration: FocusTheme.focusDecoration(
      context,
      isFocused: showFocus,
      borderRadius: tokens(context).radiusXs,
      radii: ListTileCardShape.maybeOf(context),
    ),
    child: tile,
  );
}

/// A switch or checkbox row under the redesign: Material's own focus colour
/// cleared — the plate under the row and the halo round the control — and the
/// redesign's mark in their place. Elsewhere [tile] as it is.
Widget _ockerControlRow(BuildContext context, Widget tile, {required bool focused}) {
  if (!isOcker(context)) return tile;
  final theme = Theme.of(context);
  return _ockerRowMark(
    context,
    Theme(
      data: theme.copyWith(focusColor: Colors.transparent),
      child: tile,
    ),
    showFocus: focused && InputModeTracker.isKeyboardMode(context),
  );
}

/// A SwitchListTile that accepts a FocusNode for keyboard/controller navigation.
///
/// Uses Flutter's native SwitchListTile focus support - no custom styling wrapper.
class FocusableSwitchListTile extends StatefulWidget {
  /// The primary content of the list tile.
  final Widget? title;

  /// Additional content displayed below the title.
  final Widget? subtitle;

  /// A widget to display on the opposite side from the switch.
  final Widget? secondary;

  /// Whether this switch is checked.
  final bool value;

  /// Called when the user toggles the switch.
  final ValueChanged<bool>? onChanged;

  /// Whether this switch is part of a vertically dense list.
  final bool dense;

  /// Optional FocusNode for keyboard/controller navigation.
  final FocusNode? focusNode;

  /// Whether this tile should autofocus when first built.
  final bool autofocus;

  /// Visual density for the list tile.
  final VisualDensity? visualDensity;

  /// Content padding, e.g. to align with sibling rows. Null uses the
  /// SwitchListTile default.
  final EdgeInsetsGeometry? contentPadding;

  /// Horizontal gap between the leading/secondary widget and title.
  final double? horizontalTitleGap;

  /// Minimum width reserved for the leading/secondary widget.
  final double? minLeadingWidth;

  const FocusableSwitchListTile({
    super.key,
    this.title,
    this.subtitle,
    this.secondary,
    required this.value,
    required this.onChanged,
    this.dense = true,
    this.focusNode,
    this.autofocus = false,
    this.visualDensity = const VisualDensity(vertical: -3),
    this.contentPadding,
    this.horizontalTitleGap,
    this.minLeadingWidth,
  });

  @override
  State<FocusableSwitchListTile> createState() => _FocusableSwitchListTileState();
}

class _FocusableSwitchListTileState extends State<FocusableSwitchListTile>
    with FocusableTileStateMixin<FocusableSwitchListTile> {
  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  Widget build(BuildContext context) {
    final automotive = PlatformDetector.isAutomotive();
    return ClickableCursor(
      enabled: widget.onChanged != null,
      child: _ockerControlRow(
        context,
        focused: isTileFocused,
        SwitchListTile(
          title: widget.title,
          subtitle: widget.subtitle,
          secondary: widget.secondary,
          value: widget.value,
          onChanged: widget.onChanged,
          dense: automotive ? false : widget.dense,
          visualDensity: automotive ? VisualDensity.standard : widget.visualDensity,
          contentPadding: widget.contentPadding,
          focusNode: effectiveFocusNode,
          autofocus: widget.autofocus,
          horizontalTitleGap: widget.horizontalTitleGap,
          minLeadingWidth: widget.minLeadingWidth,
        ),
      ),
    );
  }
}

/// A CheckboxListTile that accepts a FocusNode for keyboard/controller navigation.
///
/// Uses Flutter's native CheckboxListTile focus support - no custom styling wrapper.
class FocusableCheckboxListTile extends StatefulWidget {
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool tristate;
  final bool dense;
  final FocusNode? focusNode;
  final bool autofocus;
  final VisualDensity? visualDensity;
  final EdgeInsetsGeometry? contentPadding;
  final ListTileControlAffinity controlAffinity;

  const FocusableCheckboxListTile({
    super.key,
    this.title,
    this.subtitle,
    this.secondary,
    required this.value,
    required this.onChanged,
    this.tristate = false,
    this.dense = true,
    this.focusNode,
    this.autofocus = false,
    this.visualDensity = const VisualDensity(vertical: -3),
    this.contentPadding,
    this.controlAffinity = ListTileControlAffinity.platform,
  });

  @override
  State<FocusableCheckboxListTile> createState() => _FocusableCheckboxListTileState();
}

class _FocusableCheckboxListTileState extends State<FocusableCheckboxListTile>
    with FocusableTileStateMixin<FocusableCheckboxListTile> {
  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  Widget build(BuildContext context) {
    final automotive = PlatformDetector.isAutomotive();
    return ClickableCursor(
      enabled: widget.onChanged != null,
      child: _ockerControlRow(
        context,
        focused: isTileFocused,
        CheckboxListTile(
          title: widget.title,
          subtitle: widget.subtitle,
          secondary: widget.secondary,
          value: widget.value,
          onChanged: widget.onChanged,
          tristate: widget.tristate,
          dense: automotive ? false : widget.dense,
          visualDensity: automotive ? VisualDensity.standard : widget.visualDensity,
          contentPadding: widget.contentPadding,
          focusNode: effectiveFocusNode,
          autofocus: widget.autofocus,
          controlAffinity: widget.controlAffinity,
        ),
      ),
    );
  }
}

/// The corners of the card a row fills, for the row's focus ring to follow.
///
/// Set by what draws the card ([SettingsGroup]), read by [FocusableListTile]:
/// a ring drawn inside a clipped card has to have the card's own corners, or
/// the clip cuts its ends off.
class ListTileCardShape extends InheritedWidget {
  const ListTileCardShape({super.key, required this.radii, required super.child});

  final BorderRadius radii;

  static BorderRadius? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ListTileCardShape>()?.radii;

  @override
  bool updateShouldNotify(ListTileCardShape oldWidget) => radii != oldWidget.radii;
}
