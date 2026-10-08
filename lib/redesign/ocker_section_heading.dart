import 'package:flutter/material.dart';

import '../theme/mono_tokens.dart';
import 'ocker_skin.dart';
import 'ocker_type.dart';

/// A section's name and how many titles are in it.
///
/// The whole of the design's sectioning: no card, no background, no glyph in
/// front of the words. Mono uppercase says "this is a label, not a title",
/// which is the same job the bold grotesque does in the other direction.
///
/// There was a hairline running out to the right edge of every heading, meant
/// as the line the eye comes back to when it drops a row. Over a page of
/// shelves it was a dozen faint rules pointing at nothing, and the posters
/// under each name already say where a row begins. What is left of it is the
/// resume row's — see [inProgress] — which is not a rule but a mark.
class OckerSectionHeading extends StatelessWidget {
  final String title;

  /// Shown after the title. Null hides it — some sections do not know their
  /// own length until the server says so.
  final int? count;

  /// A section further down the page, which the viewer has not reached yet.
  /// Drawn dimmer so the one being read stays the loudest thing on screen.
  final bool trailing;

  /// Right-aligned words on the same line — sort order, filters. The active
  /// one is at full strength.
  final List<Widget> filters;

  /// Draws this section's rule in the accent instead of in ink.
  ///
  /// For the resume row, and only for it. Every other row on the page is a
  /// list of titles; this one is a list of *positions*, and until now the only
  /// thing saying so was a 2 px bar at the foot of each poster, which at
  /// television distance is not saying it at all. The rule is the one part of
  /// a heading that runs the whole width, so it is the one part that can mark
  /// a row rather than a tile.
  ///
  /// Not a fourth job for the accent: progress is the first of its three, and
  /// this is that job at the size of a row rather than the size of a poster.
  final bool inProgress;

  const OckerSectionHeading({
    super.key,
    required this.title,
    this.count,
    this.trailing = false,
    this.filters = const [],
    this.inProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    final scale = ockerScale(context);

    return Row(
      crossAxisAlignment: .center,
      children: [
        Text(
          type.headingCase(title),
          style: type.sectionHeading.copyWith(
            color: type.flat ? tk.ink(trailing ? 0.62 : 0.94) : (trailing ? tk.ink(0.42) : tk.ink(1)),
          ),
        ),
        if (count != null) ...[
          SizedBox(width: (type.flat ? 14 : 12) * scale),
          Text('$count', style: type.counter.copyWith(color: tk.ink(type.flat ? 0.40 : 0.38))),
        ],
        SizedBox(width: 16 * scale),
        // The room stays whether or not anything is drawn in it: it is what
        // holds the filter words out at the right edge.
        Expanded(
          child: inProgress
              ? Container(
                  height: 1,
                  // Dimmed further down the page for the same reason the words
                  // are: the section being read stays the loudest thing on
                  // screen, accent or not.
                  color: tk.accent.withValues(alpha: trailing ? 0.45 : 1),
                )
              : const SizedBox.shrink(),
        ),
        for (final filter in filters) ...[SizedBox(width: 18 * scale), filter],
      ],
    );
  }
}
