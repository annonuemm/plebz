import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/screens/livetv/tabs/guide_tab.dart';

/// The day picker offers only the days a guide has programmes for: an IPTV
/// provider's guide often ends after a day or two, and a day without data
/// opens an empty grid.
void main() {
  final today = DateTime(2026, 10, 2);
  DateTime day(int offset) => DateTime(2026, 10, 2 + offset);

  test('ahead only as far as a programme begins', () {
    // The last programme begins on the 4th in the morning.
    final days = guidePickerDays(today, archiveDays: 0, lastProgrammeStart: DateTime(2026, 10, 4, 6, 30));

    expect(days, [day(0), day(1), day(2)]);
  });

  test('a programme beginning exactly at midnight counts for that day', () {
    final days = guidePickerDays(today, archiveDays: 0, lastProgrammeStart: DateTime(2026, 10, 3));

    expect(days, [day(0), day(1)]);
  });

  test('a guide reaching past the week still offers the week, no more', () {
    final days = guidePickerDays(today, archiveDays: 0, lastProgrammeStart: DateTime(2026, 10, 30));

    expect(days, [for (var i = 0; i <= 7; i++) day(i)]);
  });

  test('an unknown reach (a server guide) offers the whole week as before', () {
    final days = guidePickerDays(today, archiveDays: 0, lastProgrammeStart: null);

    expect(days, [for (var i = 0; i <= 7; i++) day(i)]);
  });

  test('a guide ending today leaves today alone, and the archive days stay', () {
    final days = guidePickerDays(today, archiveDays: 2, lastProgrammeStart: DateTime(2026, 10, 2, 22));

    expect(days, [day(-2), day(-1), day(0)]);
  });
}
