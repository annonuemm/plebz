import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant;
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/focusable_tab_chip.dart';

import '../test_helpers/prefs.dart';

/// One shared widget carries every tab strip in the app — the watchlist's
/// provider switcher, season tabs, library tabs, the Live-TV group bar. What it
/// draws for "switched on" is therefore the app's whole answer to that
/// question, which is why Ocker changes it here rather than screen by screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetSharedPreferencesForTest);

  Future<void> pumpChips(WidgetTester tester, AppThemeVariant variant) async {
    await tester.pumpWidget(
      InputModeTracker(
        child: MaterialApp(
          theme: monoTheme(dark: true, variant: variant),
          home: Scaffold(
            body: Row(
              children: [
                FocusableTabChip(label: 'Empfohlen', isSelected: true, onSelect: () {}),
                FocusableTabChip(label: 'Durchsuchen', isSelected: false, onSelect: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Every fill painted behind [label], plate or underline.
  List<Color> fillsBehind(WidgetTester tester, String label) => [
    ...tester
        .widgetList<AnimatedContainer>(find.ancestor(of: find.text(label), matching: find.byType(AnimatedContainer)))
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .nonNulls,
    ...tester
        .widgetList<Container>(
          find.descendant(
            of: find.ancestor(of: find.text(label), matching: find.byType(FocusableTabChip)).first,
            matching: find.byType(Container),
          ),
        )
        .map((c) => c.color)
        .nonNulls,
  ];

  Color labelColorOf(WidgetTester tester, String label) => tester.widget<Text>(find.text(label)).style!.color!;

  group('Ocker', () {
    testWidgets('never shows the red the other variants use', (tester) async {
      await pumpChips(tester, AppThemeVariant.glas);

      // A second accent is the one thing a monochrome design cannot afford,
      // and this red appears nowhere else in the styleguide.
      for (final label in ['Empfohlen', 'Durchsuchen']) {
        expect(fillsBehind(tester, label), isNot(contains(activeTabChipColor)), reason: label);
        expect(labelColorOf(tester, label), isNot(activeTabChipColor), reason: label);
      }
    });

    testWidgets('separates the active word from the sleeping ones by weight and ink', (tester) async {
      await pumpChips(tester, AppThemeVariant.glas);

      final active = tester.widget<Text>(find.text('Empfohlen')).style!;
      final sleeping = tester.widget<Text>(find.text('Durchsuchen')).style!;

      expect(active.fontWeight, FontWeight.w600);
      expect(sleeping.fontWeight, FontWeight.w500);
      expect(active.color!.a, greaterThan(sleeping.color!.a));
      expect(active.fontSize, sleeping.fontSize, reason: 'same size, or the row reflows as the selection moves');
    });

    testWidgets('reserves the rule height on every tab, so the row cannot jump', (tester) async {
      await pumpChips(tester, AppThemeVariant.glas);

      final heights = ['Empfohlen', 'Durchsuchen'].map(
        (label) => tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(FocusableTabChip)).first),
      );

      expect(heights.first.height, heights.last.height);
    });
  });

  group('the other variants are untouched', () {
    testWidgets('Standard still fills the active tab with its red', (tester) async {
      await pumpChips(tester, AppThemeVariant.standard);

      expect(fillsBehind(tester, 'Empfohlen'), contains(activeTabChipColor));
      expect(labelColorOf(tester, 'Empfohlen'), onActiveTabChipColor);
    });

    testWidgets('Klar does too', (tester) async {
      await pumpChips(tester, AppThemeVariant.klar);

      expect(fillsBehind(tester, 'Empfohlen'), contains(activeTabChipColor));
    });
  });
}
