import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_symbols_icons/symbols_map.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/app_glyphs.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:plezy/widgets/plebz_symbols.g.dart';

/// The app's own glyphs (Plebz, the user's call 2026-11-03): Apple's look from
/// CupertinoIcons, the rest drawn for Plebz, in place of Material Symbols.
void main() {
  tearDown(() {
    debugPlebzGlyphs = null;
    debugOckerAppleSystemFont = null;
    applyIconDefaultsFor(AppThemeVariant.standard);
  });

  Icon drawn(WidgetTester tester) => tester.widget<Icon>(find.byType(Icon));

  Future<void> pump(WidgetTester tester, Widget icon) =>
      tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: Center(child: icon)));

  testWidgets('both redesigns draw the glyph a little smaller in the same square', (tester) async {
    debugPlebzGlyphs = true;
    for (final variant in [AppThemeVariant.glasV2, AppThemeVariant.flach]) {
      applyIconDefaultsFor(variant);
      await pump(tester, const AppIcon(Symbols.home_rounded, size: 40));

      expect(drawn(tester).icon, CupertinoIcons.house, reason: '$variant');
      expect(drawn(tester).size, closeTo(40 * AppIconDefaults.glyphScale, 1e-9));
      expect(tester.getSize(find.byType(AppIcon)), const Size.square(40));
    }
  });

  testWidgets('Apple\'s rule: a fill only for a state or a small marker', (tester) async {
    debugPlebzGlyphs = true;
    applyIconDefaultsFor(AppThemeVariant.glasV2);

    // A fill out of habit gives way to the outline.
    await pump(tester, const AppIcon(Symbols.favorite_rounded, fill: 1));
    expect(drawn(tester).icon, CupertinoIcons.heart);

    // A set favourite is a state.
    await pump(tester, const AppIcon(Symbols.favorite_rounded, fill: 1, marksState: true));
    expect(drawn(tester).icon, CupertinoIcons.heart_fill);

    // A rating's star in a line of text.
    await pump(tester, const AppIcon(Symbols.star_rounded, fill: 1, size: 12));
    expect(drawn(tester).icon, CupertinoIcons.star_fill);

    // Playback is filled by name, whatever the fill says.
    await pump(tester, const AppIcon(Symbols.pause_rounded));
    expect(drawn(tester).icon, CupertinoIcons.pause_fill);

    // A glyph without a filled twin stays as it is.
    await pump(tester, const AppIcon(Symbols.dns_rounded, fill: 1, marksState: true));
    expect(drawn(tester).icon, PlebzSymbols.server_rack);
  });

  testWidgets('Apple\'s substitutes come first, then the glyph', (tester) async {
    debugPlebzGlyphs = true;
    debugOckerAppleSystemFont = true;
    applyIconDefaultsFor(AppThemeVariant.glasV2);

    await pump(tester, const AppIcon(Symbols.more_vert_rounded));
    expect(drawn(tester).icon, CupertinoIcons.ellipsis);

    debugOckerAppleSystemFont = false;
    applyIconDefaultsFor(AppThemeVariant.glasV2);
    await pump(tester, const AppIcon(Symbols.more_vert_rounded));
    expect(drawn(tester).icon, CupertinoIcons.ellipsis_vertical);
  });

  testWidgets('Original and flutter test keep Material Symbols', (tester) async {
    debugPlebzGlyphs = true;
    applyIconDefaultsFor(AppThemeVariant.standard);
    await pump(tester, const AppIcon(Symbols.home_rounded));
    expect(drawn(tester).icon, Symbols.home_rounded);

    debugPlebzGlyphs = null;
    applyIconDefaultsFor(AppThemeVariant.glasV2);
    await pump(tester, const AppIcon(Symbols.home_rounded));
    expect(drawn(tester).icon, Symbols.home_rounded);
  });

  test('every Material Symbol the app names has a glyph', () {
    final named = <String>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final match in RegExp(r'\bSymbols\.(\w+)').allMatches(file.readAsStringSync())) {
        named.add(match.group(1)!);
      }
    }
    final missing = [
      for (final name in named)
        if (materialSymbolsMap[name] case final icon? when !plebzGlyphs.containsKey(icon)) name,
    ]..sort();
    expect(named, isNotEmpty);
    expect(missing, isEmpty, reason: 'add these to plebzGlyphs (lib/widgets/app_glyphs.dart)');
  });

  test('glyphs come from the two fonts the app bundles', () {
    for (final glyph in [...plebzGlyphs.values, ...plebzFilledGlyphs.values]) {
      expect(glyph.fontFamily, anyOf(CupertinoIcons.iconFont, PlebzSymbols.family));
    }
  });
}
