import 'package:flutter/material.dart';

import '../focus/input_mode_tracker.dart';
import '../i18n/strings.g.dart';
import '../media/library_copy_quality.dart';
import '../media/media_item.dart';
import '../redesign/ocker_skin.dart';
import '../theme/mono_tokens.dart';
import '../utils/layout_constants.dart';
import '../utils/platform_detector.dart';
import 'backend_badge.dart';
import 'library_copy_tile.dart';

/// The Explore page's way into the title on the viewer's own server: the best
/// copy there is, named by its library, with what makes it the best.
///
/// Drawn like the Play button on a library detail page, whose job it shares
/// here: a filled box in the redesign, cornered like its panels, a pill in the
/// other themes; focus fills it rather than ringing it. [copy] is null while
/// the copies are still being compared, which draws a spinner in the logo's
/// place and leaves the button inert.
class LibraryCopyJumpButton extends StatelessWidget {
  const LibraryCopyJumpButton({
    super.key,
    required this.copy,
    required this.quality,
    required this.showFocus,
    required this.onPressed,
  });

  final MediaItem? copy;
  final LibraryCopyQuality? quality;
  final bool showFocus;
  final VoidCallback? onPressed;

  /// The one or two facts that set a copy apart, short enough to sit in a
  /// button: "4K · DV".
  static String? detailOf(MediaItem copy, LibraryCopyQuality? quality) {
    final labels = quality?.labels ?? const <String>[];
    if (labels.isNotEmpty) return labels.take(2).join(' · ');
    return bestVersionLabel(copy);
  }

  @override
  Widget build(BuildContext context) {
    final isTv = PlatformDetector.isTV();
    final scale = isTv ? TvLayoutConstants.scaleOf(context) : 1.0;
    final height = (isTv ? 46.0 : 48.0) * scale;
    final keyboard = InputModeTracker.isKeyboardMode(context) || isTv;
    final colorScheme = Theme.of(context).colorScheme;
    final ocker = isOcker(context);
    final glass = ockerGlass(context);
    final tk = tokens(context);

    final Color background;
    final Color foreground;
    final OutlinedBorder shape;
    if (ocker) {
      background = showFocus ? tk.ink(1) : tk.ink(0.12);
      foreground = glass ? tk.ink(showFocus ? 1 : 0.85) : (showFocus ? tk.bg : tk.ink(0.9));
      shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(tk.radiusSm));
    } else if (keyboard) {
      background = showFocus
          ? colorScheme.inverseSurface
          : colorScheme.secondaryContainer.withValues(alpha: isTv ? 0.38 : 1);
      foreground = showFocus ? colorScheme.onInverseSurface : colorScheme.onSecondaryContainer;
      shape = const StadiumBorder();
    } else {
      background = colorScheme.primary;
      foreground = colorScheme.onPrimary;
      shape = const StadiumBorder();
    }

    final copy = this.copy;
    final label = copy == null ? t.explore.comparingCopies : libraryCopyName(copy);
    final detail = copy == null ? null : detailOf(copy, quality);
    final textStyle = TextStyle(fontSize: (isTv ? 17 : 16) * scale, fontWeight: FontWeight.w700, color: foreground);
    final iconSize = (isTv ? 20 : 18) * scale;

    return Semantics(
      label: copy == null ? label : t.explore.openCopy(library: label),
      button: true,
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: FilledButton(
          onPressed: onPressed,
          style: ButtonStyle(
            padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18 * scale)),
            minimumSize: WidgetStatePropertyAll(Size(0, height)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            // The fill is the focus mark; Material's own overlay would dim it.
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            // Under glass bare on its row's band, whose capsule shows focus.
            backgroundColor: WidgetStatePropertyAll(glass ? Colors.transparent : background),
            foregroundColor: WidgetStatePropertyAll(foreground),
            shape: WidgetStatePropertyAll(shape),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (copy == null)
                SizedBox.square(
                  dimension: iconSize,
                  child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
                )
              else
                BackendBadge(backend: copy.backend, size: iconSize, color: foreground),
              SizedBox(width: 8 * scale),
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
              ),
              if (detail != null) ...[
                SizedBox(width: 10 * scale),
                Text(
                  detail,
                  maxLines: 1,
                  style: textStyle.copyWith(fontWeight: FontWeight.w500, color: foreground.withValues(alpha: 0.7)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
