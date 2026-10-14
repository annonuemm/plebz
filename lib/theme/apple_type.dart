import 'package:flutter/painting.dart';

/// SF Pro set the way Apple sets it (Plebz, Apple builds only): the cut and the
/// letter spacing follow the point size.
///
/// Apple's own text does this by itself. Flutter names the system face through
/// two fixed stand-ins, `CupertinoSystemText` and `CupertinoSystemDisplay`, and
/// leaves both choices to the app: the text cut is drawn for reading sizes and
/// runs loose and round as a title, and neither tracks itself by size. The
/// redesign's spacing was tuned for Inter, which SF Pro replaces here (see
/// `ockerAppleSystemFont`).
///
/// [pointsPerPixel] is what one logical pixel is in Apple's points: 2 on the
/// Apple TV, which renders a half-size surface scaled up, 1 everywhere else.
///
/// [keepSpacedOut] keeps a positive spacing a style chose for itself — the
/// redesign's tracked capitals. Off for Material's defaults, whose spacing was
/// drawn for Roboto.
TextStyle appleSystemType(TextStyle style, {double pointsPerPixel = 1, bool keepSpacedOut = true}) {
  final family = style.fontFamily;
  final size = style.fontSize;
  if (size == null || (family != appleSystemTextFamily && family != appleSystemDisplayFamily)) return style;
  final points = size * pointsPerPixel;
  final spacing = style.letterSpacing ?? 0;
  return style.copyWith(
    // From 20 points the display cut, as Apple and Flutter's own notes on
    // these two names advise.
    fontFamily: points >= 20 ? appleSystemDisplayFamily : appleSystemTextFamily,
    // Letters spaced out on purpose — the redesign's tracked capitals — keep
    // their spacing; a tightening meant for Inter gives way to Apple's own.
    letterSpacing: keepSpacedOut && spacing > 0 ? spacing : appleTrackingEm(points) * size,
  );
}

/// Flutter's names for the Apple system face: SF Pro's text cut and its
/// display cut.
const appleSystemTextFamily = 'CupertinoSystemText';
const appleSystemDisplayFamily = 'CupertinoSystemDisplay';

/// Apple's tracking for SF Pro at [points], in ems (HIG, Typography → Tracking
/// values; the same table for iOS, iPadOS, macOS and tvOS). Between the
/// table's sizes the nearer value is taken, outside it the end's.
double appleTrackingEm(double points) {
  if (points <= _trackingTable.first.$1) return _trackingTable.first.$2 / 1000;
  if (points >= _trackingTable.last.$1) return _trackingTable.last.$2 / 1000;
  for (var i = 1; i < _trackingTable.length; i++) {
    final (size, milli) = _trackingTable[i];
    if (points <= size) {
      final (lower, lowerMilli) = _trackingTable[i - 1];
      return (points - lower < size - points ? lowerMilli : milli) / 1000;
    }
  }
  return 0;
}

/// Point size → thousandths of an em.
const _trackingTable = <(double, int)>[
  (6, 41), (7, 34), (8, 26), (9, 19), (10, 12), (11, 6), (12, 0), (13, -6), (14, -11), (15, -16), //
  (16, -20), (17, -26), (18, -25), (19, -24), (20, -23), (21, -18), (22, -12), (23, -4), (24, 3), //
  (25, 6), (26, 8), (27, 11), (28, 14), (29, 14), (30, 14), (31, 13), (32, 13), (33, 12), (34, 12), //
  (35, 11), (36, 10), (37, 10), (38, 10), (39, 10), (40, 10), (41, 9), (42, 9), (43, 9), (44, 8), //
  (45, 8), (46, 8), (47, 8), (48, 8), (49, 7), (50, 7), (51, 7), (52, 6), (53, 6), (54, 6), (56, 6), //
  (58, 5), (60, 4), (62, 4), (64, 4), (66, 3), (68, 2), (70, 2), (72, 2), (76, 1), (80, 0),
];
