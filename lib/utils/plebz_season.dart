import 'package:flutter/painting.dart';

import '../services/settings_service.dart';

/// The seasons the start screen dresses up for (fork addition). Each brings
/// its own logo colours and a scene behind the logo; the name stays white.
enum PlebzSeason {
  /// 17 to 31 October: a thunderstorm night with a full moon, bare trees and
  /// bats; the mark in pumpkin orange.
  halloween(markColours: [Color(0xFFC2410C), Color(0xFFFF7A1A), Color(0xFFFFB547)], glowColour: Color(0xFFFF7A1A)),

  /// 1 to 26 December: the mark as a red garland with lights, baubles and a
  /// star at its point, light snow and a string of lights along the top.
  christmas(markColours: [Color(0xFF9E0E24), Color(0xFFD7262F), Color(0xFFF2545B)], glowColour: Color(0xFFF4C05A));

  const PlebzSeason({required this.markColours, required this.glowColour});

  /// The mark's gradient, three stops like the logo's own.
  final List<Color> markColours;

  /// The light that blooms behind the logo.
  final Color glowColour;
}

/// The season [moment] falls in, by the device's own calendar: a moment
/// given in UTC is read in local time first, so the scene changes at local
/// midnight.
PlebzSeason? plebzSeasonOn(DateTime moment) {
  final day = moment.toLocal();
  return switch (day.month) {
    10 when day.day >= 17 => PlebzSeason.halloween,
    12 when day.day <= 26 => PlebzSeason.christmas,
    _ => null,
  };
}

/// The season the start screen shows now, or null outside both windows or
/// with the switch turned off.
PlebzSeason? plebzStartSeason({DateTime? now}) {
  final enabled = SettingsService.instanceOrNull?.read(PlebzPrefs.seasonalStartScreen) ?? true;
  return enabled ? plebzSeasonOn(now ?? DateTime.now()) : null;
}
