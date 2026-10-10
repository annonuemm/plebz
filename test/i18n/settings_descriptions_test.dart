import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The settings say what a row does in one short sentence at most (Plebz, the
/// user's rule): every German description the settings pages show is checked
/// here, so an upstream merge that brings a paragraph back is caught.
void main() {
  final de = jsonDecode(File('lib/i18n/de.i18n.json').readAsStringSync()) as Map<String, dynamic>;

  String? lookup(String path) {
    Object? node = de;
    for (final part in path.split('.')) {
      if (node is! Map<String, dynamic> || !node.containsKey(part)) return null;
      node = node[part];
    }
    return node is String ? node : null;
  }

  final keys = <String>{};
  final reference = RegExp(r'\bt\.([A-Za-z0-9_.]+(?:Description|Subtitle|Hint))\b');
  for (final file in Directory('lib/screens/settings').listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    for (final match in reference.allMatches(file.readAsStringSync())) {
      keys.add(match.group(1)!);
    }
  }

  test('finds the descriptions it checks', () {
    expect(keys.length, greaterThan(100));
  });

  test('every settings description is one short sentence at most', () {
    // A full stop after a number is an ordinal ("1. Bundesliga"), not an end.
    final secondSentence = RegExp(r'(?<![0-9])[.!?…]\s+\S');
    final tooLong = <String>[];
    for (final key in keys) {
      final text = lookup(key);
      if (text == null) continue;
      if (text.length > 100 || secondSentence.hasMatch(text)) tooLong.add('$key: $text');
    }
    expect(tooLong, isEmpty);
  });
}
