import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/card_focus_scope.dart';
import '../focus/focusable_wrapper.dart';
import '../i18n/strings.g.dart';
import '../navigation/profile_navigation_scope.dart';
import '../redesign/ocker_skin.dart';
import '../theme/mono_tokens.dart';
import 'app_bar_back_button.dart';
import 'app_icon.dart';

/// Leaves a run of detail pages for the home tab in one step.
///
/// Detail pages open one from another — a title, its cast, another title —
/// and the way back was a back press for each. This closes them all and shows
/// the home tab ([ProfileNavigationRegistry.goHome]). Where there is no main
/// screen below, it only closes the page it stands on.
void goHomeFromDetail(BuildContext context) {
  if (!profileNavigationRegistry.goHome()) Navigator.maybePop(context);
}

/// The home button beside a detail page's back arrow, in the arrow's own
/// look — phone, tablet and desktop, where the arrow is drawn.
class DetailHomeBesideBack extends StatelessWidget {
  const DetailHomeBesideBack({super.key});

  @override
  Widget build(BuildContext context) => AppBarBackButton(
    style: BackButtonStyle.circular,
    icon: Symbols.home_rounded,
    semanticLabel: t.common.home,
    onPressed: () => goHomeFromDetail(context),
  );
}

/// The home button in a detail page's top left corner on a television, where
/// no back arrow is drawn: the remote's back key leaves one page, this leaves
/// them all. The D-pad reaches it by UP from the page's action row.
///
/// A round pane of glass under "Redesign – Glas", lit while focused; a dark
/// disc with the theme's focus ring everywhere else.
class DetailHomeButton extends StatelessWidget {
  const DetailHomeButton({super.key, this.focusNode, this.onNavigateDown, this.size = 40});

  final FocusNode? focusNode;

  /// Back to the action row the button was reached from.
  final VoidCallback? onNavigateDown;

  final double size;

  @override
  Widget build(BuildContext context) {
    final glass = ockerGlass(context);
    final label = t.common.home;
    void noMove() {}
    return FocusableWrapper(
      focusNode: focusNode,
      semanticLabel: label,
      onSelect: () => goHomeFromDetail(context),
      onNavigateDown: onNavigateDown,
      // Nothing beside or above it: the press is spent here rather than
      // wandering off into the artwork.
      onNavigateUp: noMove,
      onNavigateLeft: noMove,
      onNavigateRight: noMove,
      autoScroll: false,
      disableScale: true,
      descendantsAreFocusable: false,
      borderRadius: size / 2,
      delegateFocusBorder: glass,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: () => goHomeFromDetail(context),
          child: SizedBox.square(
            dimension: size,
            child: glass ? _GlassHomeFace(size: size) : _DiscHomeFace(size: size),
          ),
        ),
      ),
    );
  }
}

class _DiscHomeFace extends StatelessWidget {
  const _DiscHomeFace({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), shape: BoxShape.circle),
    child: Center(
      child: AppIcon(Symbols.home_rounded, fill: 1, color: Colors.white, size: size / 2),
    ),
  );
}

/// A quiet pane of glass at rest and a bright one while focused, as the
/// redesign's capsules are.
class _GlassHomeFace extends StatelessWidget {
  const _GlassHomeFace({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    // Null off the D-pad, where no focus is shown.
    final focused = CardFocusScope.maybeOf(context) ?? false;
    final tk = tokens(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        OckerGlassFocusFill(shape: const CircleBorder(), bright: focused),
        Center(
          // On a flat focus fill (white) the glyph goes dark.
          child: AppIcon(
            Symbols.home_rounded,
            color: focused ? (tk.flat ? tk.bg : tk.ink(1)) : tk.ink(0.85),
            size: size / 2,
          ),
        ),
      ],
    );
  }
}
