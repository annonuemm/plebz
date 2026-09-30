import 'package:flutter/material.dart';

import '../../redesign/ocker_skin.dart';
import '../../redesign/ocker_type.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/focusable_tab_chip.dart' show activeTabChipColor;

/// How the Sport destination is drawn in the theme that is on.
///
/// One set of widgets serves both, and this is the one place they differ in
/// appearance. The redesign sets everything in its own type scale — measured
/// against a 1920-wide reference and scaled from there — keeps figures
/// tabular, puts labels in its mono roles and reserves its accent for "now".
/// The standard theme takes the Material text theme, grows it on a television
/// the way the rest of that theme does, and marks a running match in the same
/// red as its active tab chip.
///
/// Where the two also differ in *structure* — the redesign has no chip row for
/// the leagues and no side rail to walk back to — that is decided by the
/// screen, not here.
class SportLook {
  SportLook._(this.context, {required this.ocker, required this.scale, required this.tk});

  factory SportLook.of(BuildContext context) {
    final ocker = isOckerLayout(context);
    final double scale;
    if (ocker) {
      scale = ockerScale(context);
    } else if (PlatformDetector.isTV()) {
      scale = TvLayoutConstants.scaleOf(context);
    } else {
      scale = 1.0;
    }
    return SportLook._(context, ocker: ocker, scale: scale, tk: tokens(context));
  }

  final BuildContext context;
  final bool ocker;
  final double scale;
  final MonoTokens tk;

  OckerType get _type => OckerType(scale);
  TextTheme get _text => Theme.of(context).textTheme;

  Color ink(double opacity) => tk.ink(opacity);

  /// The one colour a running match gets.
  Color get live => ocker ? tk.accent : activeTabChipColor;

  /// Room for a crest, square.
  double get crest => (ocker ? 34 : 24) * scale;

  /// One match line. Tall enough for a crest with air around it; the list is
  /// read top to bottom and nine to ten of these make a matchday.
  double get matchRowHeight => (ocker ? 64 : 48) * scale;

  double get gap => (ocker ? 18 : 12) * scale;

  /// A club's name in a fixture line.
  TextStyle teamName({bool strong = false}) => ocker
      ? TextStyle(
          fontFamily: _type.body.fontFamily,
          fontSize: 22 * scale,
          fontWeight: strong ? .w700 : .w500,
          height: 1.1,
        )
      : (_text.titleMedium ?? const TextStyle()).copyWith(
          fontSize: 16 * scale,
          fontWeight: strong ? .w700 : .w500,
          height: 1.1,
        );

  /// The score between the two names, and the kickoff where there is none yet.
  TextStyle score({bool strong = true}) => TextStyle(
    fontFamily: ocker ? _type.metadata.fontFamily : _text.titleLarge?.fontFamily,
    fontSize: (ocker ? 26 : 19) * scale,
    fontWeight: strong ? .w700 : .w500,
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// The time column at the left of a fixture line.
  TextStyle get time => ocker
      ? _type.timecode.copyWith(fontSize: 17 * scale)
      : (_text.bodyMedium ?? const TextStyle()).copyWith(
          fontSize: 14 * scale,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

  /// "FREITAG, 18. SEPTEMBER", "TABELLE" — a label over a block.
  TextStyle get heading => ocker
      ? _type.sectionHeading
      : (_text.labelLarge ?? const TextStyle()).copyWith(fontSize: 13 * scale, letterSpacing: 1.2 * scale);

  /// A matchday in the strip.
  TextStyle matchdayChip({required bool current}) => ocker
      ? _type.groupEntry(active: current)
      : (_text.labelLarge ?? const TextStyle()).copyWith(fontSize: 14 * scale, fontWeight: current ? .w700 : .w500);

  /// A cell of the table.
  TextStyle tableCell({bool strong = false}) => TextStyle(
    fontFamily: ocker ? _type.metadata.fontFamily : _text.bodyMedium?.fontFamily,
    fontSize: (ocker ? 18 : 14) * scale,
    fontWeight: strong ? .w700 : .w400,
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// The small "LIVE" badge.
  TextStyle get badge => ocker
      ? _type.nowChip.copyWith(fontSize: 13 * scale)
      : (_text.labelSmall ?? const TextStyle()).copyWith(
          fontSize: 11 * scale,
          fontWeight: .w700,
          letterSpacing: 0.6 * scale,
        );

  /// Body text in the match window.
  TextStyle get body => ocker ? _type.synopsis : (_text.bodyLarge ?? const TextStyle()).copyWith(fontSize: 16 * scale);
}
