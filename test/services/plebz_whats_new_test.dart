import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/plebz_whats_new.dart';

List<int> _builds(List<PlebzWhatsNewEntry> entries) => [for (final entry in entries) entry.build];

void main() {
  const notes = '''
# Was ist neu in Plebz

Anything above the first version is not a note.

## 1.2.0 (Entwurf)
- Not released: no build, not shown

## 1.1.0 (Build 557)

- Second

## 1.2.0 (Build 559)
### Live TV
- First, **bold** word
  - nested

''';

  group('reading the notes', () {
    test('each version with a build is a section, newest first; a draft is not', () {
      final entries = parsePlebzWhatsNew(notes);

      expect(_builds(entries), [559, 557]);
      expect(entries.first.version, '1.2.0');
      expect(entries.first.lines, ['### Live TV', '- First, **bold** word', '  - nested']);
      expect(entries.last.lines, ['- Second'], reason: 'blank lines around a section are not part of it');
    });

    test('the file that ships reads without a fault', () {
      // Every section in it names a real build and has something to say.
      final entries = parsePlebzWhatsNew(File(plebzWhatsNewAsset).readAsStringSync());
      for (final entry in entries) {
        expect(entry.lines.where((line) => line.trim().isNotEmpty), isNotEmpty, reason: 'build ${entry.build}');
      }
    });
  });

  group('what an update tells', () {
    final entries = parsePlebzWhatsNew('''
## 1.3.0 (Build 562)
- c
## 1.2.0 (Build 560)
- b
## 1.1.0 (Build 557)
- a
''');

    test('everything after the build last started, up to the one installed', () {
      expect(_builds(plebzWhatsNewSince(entries, lastSeen: 556, current: 561)), [560, 557]);
    });

    test('a test build between releases has nothing of its own', () {
      expect(plebzWhatsNewSince(entries, lastSeen: 560, current: 561), isEmpty);
    });

    test('with nothing seen before, only the newest that is installed', () {
      expect(_builds(plebzWhatsNewSince(entries, lastSeen: 0, current: 561)), [560]);
    });
  });

  group('as text', () {
    test('bullets become dots, sub-headings and **words** bold', () {
      final span = plebzNotesSpan('### Live TV\n- First, **bold** word\n\nAfter a gap', lead: 'Lead');

      expect(span.toPlainText(), 'Lead\n\nLive TV\n•  First, bold word\n\nAfter a gap');
      final bold = <String>[];
      span.visitChildren((child) {
        if (child is TextSpan && child.style?.fontWeight == FontWeight.w700) bold.add(child.text ?? '');
        return true;
      });
      expect(bold, ['Live TV', 'bold']);
    });

    test('each version under its own bold line', () {
      final span = plebzWhatsNewSpan(parsePlebzWhatsNew(notes), lead: 'Updated');

      expect(
        span.toPlainText(),
        'Updated\n\nPlebz 1.2.0 (Build 559)\nLive TV\n•  First, bold word\n      •  nested'
        '\n\nPlebz 1.1.0 (Build 557)\n•  Second',
      );
    });
  });
}
