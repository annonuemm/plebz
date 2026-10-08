import 'package:flutter/material.dart';

import '../theme/mono_tokens.dart';

/// Unwatched-episode count chip shown in the top-right corner of poster
/// cards. Keeps a [size]-diameter circular footprint for 1–2 digit counts
/// and widens into a stadium pill beyond that; counts above 999 render as
/// "999+" so the label stays on one line (#1310).
///
/// One size on every surface. The count sits in the same corner as the other
/// poster marks and is read alongside them, so it takes their type size —
/// [defaultFontSize] with [defaultSize] of diameter, which is one line of that
/// text between its paddings. Dense surfaces used to shrink it on their own
/// and ended up with a chip *larger* than the poster's own marks.
/// The numeral inside the circle, in the face this theme gives a counter.
TextStyle _numeralStyle(BuildContext context, double fontSize) {
  final t = tokens(context);
  final mono = t.monoFontFamily;
  if (mono == null) return TextStyle(color: t.bg, fontSize: fontSize, fontWeight: FontWeight.bold);
  return TextStyle(
    color: t.bg,
    fontFamily: mono,
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

class UnwatchedCountBadge extends StatelessWidget {
  /// Diameter of the circle, matching the height of a poster's label chips.
  static const double defaultSize = 15;

  /// Type size shared with every other mark stamped on a poster.
  static const double defaultFontSize = 9;

  final int count;
  final double size;
  final double fontSize;

  const UnwatchedCountBadge({super.key, required this.count, this.size = defaultSize, this.fontSize = defaultFontSize});

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    if (tk.flat) return _buildFlat(tk);
    return Container(
      height: size,
      constraints: BoxConstraints(minWidth: size),
      // A fifth of the diameter each side was headroom at 24pt and none at
      // 15: a single digit then pushed the circle into a slight pill.
      padding: EdgeInsets.symmetric(horizontal: size * 0.15),
      decoration: BoxDecoration(
        color: tokens(context).text,
        borderRadius: BorderRadius.circular(size / 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
      ),
      // Center with widthFactor shrink-wraps the pill to the label (Container
      // alignment would expand into the Stack's loose width instead).
      child: Center(
        widthFactor: 1,
        child: Text(
          count > 999 ? '999+' : '$count',
          maxLines: 1,
          softWrap: false,
          // The same face the other marks on a poster take — mono under
          // "Ocker", where counters are one of the three jobs that family has.
          // Every other variant keeps the bold it has always had.
          style: _numeralStyle(context, fontSize),
        ),
      ),
    );
  }

  /// "Redesign – Flach" (Plebz): a dark pill with the count in ink. A row of
  /// white circles was the loudest thing on the screen; dark, the number is
  /// still read and no longer shouts. No blur behind it — a frosted chip on
  /// every poster of a row costs a weak box more than it shows.
  Widget _buildFlat(MonoTokens tk) {
    final height = size * 26 / 30;
    return Container(
      height: height,
      constraints: BoxConstraints(minWidth: size),
      padding: EdgeInsets.symmetric(horizontal: height * 0.3),
      decoration: BoxDecoration(color: tk.bg.withValues(alpha: 0.82), borderRadius: BorderRadius.circular(height / 2)),
      child: Center(
        widthFactor: 1,
        child: Text(
          count > 999 ? '999+' : '$count',
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: tk.ink(0.92),
            fontSize: fontSize * 14 / 18,
            fontWeight: FontWeight.w600,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
