import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/catalog/catalog_metadata.dart';
import 'package:plezy/utils/catalog_next_airing.dart';

/// 17:00 on a Wednesday — late enough in the day that a duration-based label
/// would disagree with a calendar-based one about tomorrow.
///
/// Unit abbreviations below are the base locale's ("w", "d"); the German build
/// reads "W" and "T". What is under test is which unit survives, not its
/// spelling — that comes from the shared duration formatter.
final _now = DateTime(2026, 9, 9, 17, 0);

String? _labelFor(DateTime airsAt, {bool is24Hour = true}) =>
    catalogNextAiringLabel(CatalogNextEpisode(airsAt: airsAt), _now, is24Hour: is24Hour);

void main() {
  // formatClockTime goes through intl, which needs its locale data loaded.
  setUpAll(() => initializeDateFormatting('en'));

  group('catalogNextAiringLabel', () {
    test('far out, it counts weeks', () {
      expect(_labelFor(DateTime(2026, 12, 23)), t.explore.badge.nextAiringIn(duration: '15w'));
    });

    test('inside a week, it counts days', () {
      expect(_labelFor(DateTime(2026, 9, 15)), t.explore.badge.nextAiringIn(duration: '6d'));
    });

    test('tomorrow is a day away, not seven hours', () {
      // The provider dated the episode without a time, so it parses to
      // midnight — seven hours off by the clock, one sleep away to a viewer.
      expect(_labelFor(DateTime(2026, 9, 10)), t.explore.badge.nextAiringIn(duration: '1d'));
    });

    test('an exact week is one week, not seven days', () {
      expect(_labelFor(DateTime(2026, 9, 16)), t.explore.badge.nextAiringIn(duration: '1w'));
    });

    test('a week and a bit keeps only the week', () {
      expect(_labelFor(DateTime(2026, 9, 18)), t.explore.badge.nextAiringIn(duration: '1w'));
    });

    test("today with a broadcast time names the hour", () {
      expect(_labelFor(DateTime(2026, 9, 9, 20, 15)), t.explore.badge.nextAiringAt(time: '20:15'));
    });

    test('today without a time says today rather than inventing midnight', () {
      expect(_labelFor(DateTime(2026, 9, 9)), t.explore.badge.nextAiringToday);
    });

    test('an hour already past today still counts as today', () {
      expect(_labelFor(DateTime(2026, 9, 9, 9, 30)), t.explore.badge.nextAiringAt(time: '09:30'));
    });

    test('a day that has passed shows nothing', () {
      expect(_labelFor(DateTime(2026, 9, 8, 23, 59)), isNull);
    });

    test('a UTC timestamp is read in local time', () {
      final airsAt = DateTime(2026, 9, 15, 12).toUtc();
      expect(_labelFor(airsAt), t.explore.badge.nextAiringIn(duration: '6d'));
    });
  });
}
