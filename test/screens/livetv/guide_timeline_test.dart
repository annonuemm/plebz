import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/screens/livetv/tabs/guide_tab.dart';

/// Epoch seconds for a time of day on one fixed date.
int _at(int hour, int minute) => DateTime.utc(2026, 9, 26, hour, minute).millisecondsSinceEpoch ~/ 1000;

LiveTvProgram _program(String title, int begins, int ends) =>
    LiveTvProgram(title: title, beginsAt: begins, endsAt: ends, channelIdentifier: 'ch');

void main() {
  group('guideTimeline', () {
    test('an entry that overruns the next ends where the next begins', () {
      final timeline = guideTimeline([
        _program('Nations League', _at(12, 0), _at(14, 56)),
        _program('Fußball', _at(14, 50), _at(17, 50)),
      ]);

      expect(timeline.map((p) => p.title), ['Nations League', 'Fußball']);
      expect(timeline.first.endsAt, _at(14, 50));
      expect(timeline.last.endsAt, _at(17, 50), reason: 'the later one keeps its own end');
    });

    test('of two with the same start, the first keeps the slot', () {
      final timeline = guideTimeline([
        _program('First', _at(14, 0), _at(14, 30)),
        _program('Second', _at(14, 0), _at(15, 10)),
      ]);

      expect(timeline.map((p) => p.title), ['First']);
    });

    test('a long entry around a shorter one gives way where it begins', () {
      final timeline = guideTimeline([
        _program('Sendepause', _at(12, 0), _at(20, 0)),
        _program('Spiel', _at(14, 0), _at(16, 0)),
      ]);

      expect(timeline.map((p) => p.title), ['Sendepause', 'Spiel']);
      expect(timeline.first.endsAt, _at(14, 0));
    });

    test('comes out in order, and entries that touch are left alone', () {
      final a = _program('A', _at(10, 0), _at(11, 0));
      final b = _program('B', _at(11, 0), _at(12, 0));
      final timeline = guideTimeline([b, a]);

      expect(timeline, [same(a), same(b)]);
    });
  });
}
