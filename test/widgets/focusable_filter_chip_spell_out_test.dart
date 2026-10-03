import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/redesign/ocker_filter_glyph.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant;
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/focusable_filter_chip.dart';

/// On the redesign's band a chip is a bare glyph — unless it asks to say what
/// it holds, as the library's sort does once one is chosen.
void main() {
  setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> pump(WidgetTester tester, {required bool spellOut}) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: Scaffold(
          body: Center(
            child: FocusableFilterChip(
              icon: Symbols.sort_rounded,
              label: 'Datum hinzugefügt ↓',
              spellOut: spellOut,
              onPressed: () {},
              focusNode: node,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the sort on show is written out', (tester) async {
    await pump(tester, spellOut: true);

    expect(find.text('Datum hinzugefügt ↓'), findsOneWidget);
    expect(find.byType(OckerFilterGlyph), findsNothing);
  });

  testWidgets('with nothing chosen the glyph stands, as before', (tester) async {
    await pump(tester, spellOut: false);

    expect(find.byType(OckerFilterGlyph), findsOneWidget);
    expect(find.text('Datum hinzugefügt ↓'), findsNothing);
  });
}
