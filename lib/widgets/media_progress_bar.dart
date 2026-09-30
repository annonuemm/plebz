import 'package:flutter/material.dart';

import '../redesign/ocker_skin.dart';
import '../theme/mono_tokens.dart';

/// Reusable media progress bar widget for displaying watch progress
///
/// Shows a linear progress indicator based on viewOffset and duration.
/// Uses theme defaults when colors are not provided.
class MediaProgressBar extends StatelessWidget {
  final int viewOffset; // Progress position in milliseconds
  final int duration; // Total duration in milliseconds
  final Color? backgroundColor;
  final Color? valueColor;
  final double? minHeight;

  const MediaProgressBar({
    super.key,
    required this.viewOffset,
    required this.duration,
    this.backgroundColor,
    this.valueColor,
    this.minHeight,
  });

  @override
  Widget build(BuildContext context) {
    final progress = duration > 0 ? viewOffset / duration : 0.0;

    final redesign = isOcker(context);

    return LinearProgressIndicator(
      value: progress.clamp(0.0, 1.0),
      // On a poster the track is a hole punched in the artwork, not a surface:
      // the bar sits on whatever photograph happens to be behind it, and a
      // theme surface colour is a guess about a ground that is not there.
      backgroundColor:
          backgroundColor ??
          (redesign ? const Color(0x80000000) : Theme.of(context).colorScheme.surfaceContainerHighest),
      // Ink, not the accent — in the redesign the accent marks the resume row
      // once, on the rule under its heading. Repeating it on every poster in
      // that row spent the colour a dozen times to say what the rule already
      // said. What the bar has to say is *how far*, and a white line on a
      // black track says that at any distance. The bar inside an opened tile
      // is a different widget and keeps the accent: there it is alone.
      valueColor: AlwaysStoppedAnimation<Color>(
        valueColor ?? (redesign ? tokens(context).ink(1) : Theme.of(context).colorScheme.primary),
      ),
      minHeight: minHeight ?? 4,
    );
  }
}
