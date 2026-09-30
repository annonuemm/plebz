import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/live_tv_group_label.dart';

String _plain(String group) => liveTvGroupLabel(group, stripCountryPrefix: false);
String _stripped(String group) => liveTvGroupLabel(group, stripCountryPrefix: true);

void main() {
  group('with the setting off', () {
    test('every name is handed back exactly as the provider wrote it', () {
      for (final group in ['DE • Doku', '[UK] Sport', 'Doku']) {
        expect(_plain(group), group);
      }
    });
  });

  group('with the setting on', () {
    test('drops the code and the separator behind it', () {
      // Rows as a typical provider playlist names them, chip for chip.
      expect(_stripped('DE • FreeTV/HD+ • RAW'), 'FreeTV/HD+ • RAW');
      expect(_stripped('DE • Nachrichten & Politik'), 'Nachrichten & Politik');
      expect(_stripped('DE • Sport • Bundesliga • RAW'), 'Sport • Bundesliga • RAW');
    });

    test('reads the other punctuation providers separate with', () {
      expect(_stripped('DE: Doku'), 'Doku');
      expect(_stripped('DE - Doku'), 'Doku');
      expect(_stripped('DE|Doku'), 'Doku');
      expect(_stripped('FR / Cinéma'), 'Cinéma');
      expect(_stripped('de · doku'), 'doku');
    });

    test('reads a bracketed code too', () {
      expect(_stripped('[DE] Doku'), 'Doku');
      expect(_stripped('(AT) Doku'), 'Doku');
      expect(_stripped('|CH| • Doku'), 'Doku');
    });

    test('takes the three-letter forms it knows', () {
      expect(_stripped('GER • Doku'), 'Doku');
      expect(_stripped('USA • News'), 'News');
    });

    test('leaves a word that merely looks like a code', () {
      // Losing these would eat the group's actual name, which is worse than
      // leaving a repeated prefix standing.
      expect(_stripped('TV • Doku'), 'TV • Doku');
      expect(_stripped('HD • Sport'), 'HD • Sport');
      expect(_stripped('VOD • Filme'), 'VOD • Filme');
      expect(_stripped('Kids • Serien'), 'Kids • Serien');
      expect(_stripped('Doku'), 'Doku');
    });

    test('leaves an unknown three-letter token alone', () {
      expect(_stripped('MAX • Serien'), 'MAX • Serien');
    });

    test('leaves mixed case alone, because that is a word', () {
      expect(_stripped('De • Doku'), 'De • Doku');
    });

    test('strips only the first code, not every separator on the line', () {
      expect(_stripped('DE • FR • Doku'), 'FR • Doku');
    });

    test('keeps a name that is nothing but a code', () {
      // An empty chip would name no group at all.
      expect(_stripped('DE'), 'DE');
      expect(_stripped('DE •'), 'DE •');
    });

    test('keeps the empty group empty', () {
      expect(_stripped(''), '');
    });
  });

  group('a name the user gave the group', () {
    test('wins over the provider name, with the setting either way', () {
      expect(liveTvGroupLabel('DE • Doku • RAW', stripCountryPrefix: false, customName: 'Doku'), 'Doku');
      expect(liveTvGroupLabel('DE • Doku • RAW', stripCountryPrefix: true, customName: 'Doku'), 'Doku');
    });

    test('is taken as written, prefix and all', () {
      // They renamed it to read what they want it to read.
      expect(liveTvGroupLabel('Sport', stripCountryPrefix: true, customName: 'DE • Sport'), 'DE • Sport');
    });

    test('is trimmed', () {
      expect(liveTvGroupLabel('Sport', stripCountryPrefix: false, customName: '  Fußball '), 'Fußball');
    });

    test('a blank one is no name and leaves the provider\'s standing', () {
      expect(liveTvGroupLabel('DE • Doku', stripCountryPrefix: true, customName: '   '), 'Doku');
      expect(liveTvGroupLabel('DE • Doku', stripCountryPrefix: false, customName: null), 'DE • Doku');
    });
  });
}
