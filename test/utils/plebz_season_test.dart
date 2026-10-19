import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/plebz_season.dart';

import '../test_helpers/prefs.dart';

void main() {
  group('plebzSeasonOn', () {
    test('Halloween runs from 17 October to the end of the 31st', () {
      expect(plebzSeasonOn(DateTime(2026, 10, 16, 23, 59, 59)), isNull);
      expect(plebzSeasonOn(DateTime(2026, 10, 17)), PlebzSeason.halloween);
      expect(plebzSeasonOn(DateTime(2026, 10, 24, 12)), PlebzSeason.halloween);
      expect(plebzSeasonOn(DateTime(2026, 10, 31, 23, 59, 59)), PlebzSeason.halloween);
      expect(plebzSeasonOn(DateTime(2026, 11, 1)), isNull);
    });

    test('Christmas runs from 1 December to the end of the 26th', () {
      expect(plebzSeasonOn(DateTime(2026, 11, 30, 23, 59, 59)), isNull);
      expect(plebzSeasonOn(DateTime(2026, 12, 1)), PlebzSeason.christmas);
      expect(plebzSeasonOn(DateTime(2026, 12, 24, 18)), PlebzSeason.christmas);
      expect(plebzSeasonOn(DateTime(2026, 12, 26, 23, 59, 59)), PlebzSeason.christmas);
      expect(plebzSeasonOn(DateTime(2026, 12, 27)), isNull);
      expect(plebzSeasonOn(DateTime(2027, 1, 1)), isNull);
    });

    test('the rest of the year is plain', () {
      for (var month = 1; month <= 9; month++) {
        expect(plebzSeasonOn(DateTime(2026, month, 20)), isNull, reason: 'month $month');
      }
      expect(plebzSeasonOn(DateTime(2026, 11, 15)), isNull);
    });

    test('the same instant in UTC is read on the device calendar', () {
      for (final local in [
        DateTime(2026, 10, 16, 23, 30),
        DateTime(2026, 10, 17, 0, 30),
        DateTime(2026, 10, 31, 23, 30),
        DateTime(2026, 11, 1, 0, 30),
        DateTime(2026, 11, 30, 23, 30),
        DateTime(2026, 12, 1, 0, 30),
        DateTime(2026, 12, 26, 23, 30),
        DateTime(2026, 12, 27, 0, 30),
      ]) {
        expect(plebzSeasonOn(local.toUtc()), plebzSeasonOn(local), reason: '$local');
      }
    });
  });

  group('plebzStartSeason', () {
    setUp(resetSharedPreferencesForTest);

    test('follows the date while the switch is on, its default', () async {
      await SettingsService.getInstance();
      expect(plebzStartSeason(now: DateTime(2026, 10, 19)), PlebzSeason.halloween);
      expect(plebzStartSeason(now: DateTime(2026, 12, 3)), PlebzSeason.christmas);
      expect(plebzStartSeason(now: DateTime(2026, 11, 3)), isNull);
    });

    test('stays plain with the switch off', () async {
      final settings = await SettingsService.getInstance();
      await settings.write(PlebzPrefs.seasonalStartScreen, false);
      expect(plebzStartSeason(now: DateTime(2026, 10, 19)), isNull);
      expect(plebzStartSeason(now: DateTime(2026, 12, 3)), isNull);
    });
  });

  test('each season has its own logo colours, three stops like the logo', () {
    for (final season in PlebzSeason.values) {
      expect(season.markColours, hasLength(3));
    }
    expect(PlebzSeason.halloween.markColours, isNot(PlebzSeason.christmas.markColours));
  });
}
