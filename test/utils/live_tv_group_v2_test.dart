import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/live_tv_group_label.dart';

void main() {
  test('a group splits into its country and the name behind it', () {
    expect(liveTvGroupCountrySplit('DE • Doku • RAW'), (country: 'DE', rest: 'Doku • RAW'));
    expect(liveTvGroupCountrySplit('[UK] News'), (country: 'UK', rest: 'News'));
    expect(liveTvGroupCountrySplit('Doku'), (country: null, rest: 'Doku'));
    expect(liveTvGroupCountrySplit('HD • Sport'), (country: null, rest: 'HD • Sport'), reason: 'HD is no country');
  });

  test('a country heading is its German name, or the code', () {
    expect(liveTvCountryHeading('DE'), 'Deutschland');
    expect(liveTvCountryHeading('nl'), 'Niederlande');
    expect(liveTvCountryHeading('XYZ'), 'XYZ');
  });

  test('the RAW mark goes where no two names would then read the same', () {
    expect(liveTvWithoutRawMark(['FreeTV/HD+ • RAW', 'Doku • RAW', 'Nachrichten']), [
      'FreeTV/HD+',
      'Doku',
      'Nachrichten',
    ]);
    expect(liveTvWithoutRawMark(['Sport • RAW', 'Sport']), ['Sport • RAW', 'Sport']);
    expect(liveTvWithoutRawMark(['RAW']), ['RAW']);
  });
}
