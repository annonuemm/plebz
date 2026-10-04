import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The four corner colours Plex derives from a title's artwork for its
/// "UltraBlur" background: one per quarter of the image, blended across the
/// screen instead of blurring the image itself.
@immutable
class UltraBlurColors {
  const UltraBlurColors({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  final Color topLeft;
  final Color topRight;
  final Color bottomRight;
  final Color bottomLeft;

  /// Reads one `UltraBlurColors` entry: hex strings, with or without `#`.
  /// Null when any corner is missing or unreadable.
  static UltraBlurColors? fromJson(Object? raw) {
    if (raw is List) raw = raw.isEmpty ? null : raw.first;
    if (raw is! Map) return null;
    final topLeft = _hex(raw['topLeft']);
    final topRight = _hex(raw['topRight']);
    final bottomRight = _hex(raw['bottomRight']);
    final bottomLeft = _hex(raw['bottomLeft']);
    if (topLeft == null || topRight == null || bottomRight == null || bottomLeft == null) return null;
    return UltraBlurColors(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft);
  }

  static Color? _hex(Object? value) {
    if (value is! String) return null;
    final digits = value.startsWith('#') ? value.substring(1) : value;
    if (digits.length != 6) return null;
    final rgb = int.tryParse(digits, radix: 16);
    return rgb == null ? null : Color(0xFF000000 | rgb);
  }

  @override
  bool operator ==(Object other) =>
      other is UltraBlurColors &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);
}
