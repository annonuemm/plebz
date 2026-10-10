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

  /// The track on a poster: a hole punched in the artwork, not a surface —
  /// the bar sits on whatever photograph is behind it, and a theme surface
  /// colour is a guess about a ground that is not there.
  static const Color posterTrack = Color(0x80000000);

  /// The bar's colour in the redesigns: white under Glas — the accent there
  /// marks the resume row once, on the rule under its heading — and the
  /// accent under Flach, as Plex draws it (the viewer's call, 2026-10-10).
  static Color redesignFill(BuildContext context) =>
      ockerFlat(context) ? tokens(context).accent : tokens(context).ink(1);

  @override
  Widget build(BuildContext context) {
    final progress = duration > 0 ? viewOffset / duration : 0.0;

    final redesign = isOcker(context);

    return LinearProgressIndicator(
      value: progress.clamp(0.0, 1.0),
      backgroundColor:
          backgroundColor ?? (redesign ? posterTrack : Theme.of(context).colorScheme.surfaceContainerHighest),
      // What the bar has to say is *how far*. The bar inside an opened tile
      // is a different widget and keeps the accent: there it is alone.
      valueColor: AlwaysStoppedAnimation<Color>(
        valueColor ?? (redesign ? redesignFill(context) : Theme.of(context).colorScheme.primary),
      ),
      minHeight: minHeight ?? 4,
    );
  }
}
