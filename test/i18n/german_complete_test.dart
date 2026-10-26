import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Plebz is used in German: every text a German viewer can see is German, not
/// English shown through slang's fallback for an empty entry. An upstream merge
/// brings English texts with empty German ones; this names them so they are
/// translated before a release (the 2.24 merge left some 45 behind).
///
/// Left out: areas this fork switches off, which no viewer reaches.
const _switchedOff = {'watchTogether', 'themeEditor', 'appIcon', 'supporter'};

/// Names, not words: the preset themes keep their English names in every
/// language (upstream's rule, pinned in theme_provider_test).
const _names = {
  'settings.emberTheme',
  'settings.glacierTheme',
  'settings.forestTheme',
  'settings.plumTheme',
  'settings.paperTheme',
};

Map<String, Object?> _flatten(Map<String, Object?> node, [String prefix = '']) => {
  for (final MapEntry(:key, :value) in node.entries)
    if (value is Map<String, Object?>) ..._flatten(value, '$prefix$key.') else '$prefix$key': value,
};

Map<String, Object?> _read(String locale) =>
    _flatten(jsonDecode(File('lib/i18n/$locale.i18n.json').readAsStringSync()) as Map<String, Object?>);

void main() {
  test('no text a German viewer can see falls back to English', () {
    final english = _read('en');
    final german = _read('de');

    final missing = [
      for (final MapEntry(:key, :value) in english.entries)
        if (value is String &&
            value.isNotEmpty &&
            !_switchedOff.contains(key.split('.').first) &&
            !_names.contains(key) &&
            (german[key] == null || german[key] == ''))
          key,
    ];

    expect(missing, isEmpty, reason: 'translate these into lib/i18n/de.i18n.json');
  });
}
