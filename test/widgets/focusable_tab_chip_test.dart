import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/focusable_tab_chip.dart';

import '../test_helpers/prefs.dart';

/// Active and focused used to be painted the same colour, which left no way to
/// tell "this is the tab I am standing on" from "this is the tab that is
/// switched on".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetSharedPreferencesForTest);

  Future<void> pumpChips(WidgetTester tester, {required FocusNode focusNode}) async {
    await tester.pumpWidget(
      InputModeTracker(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: Row(
              children: [
                FocusableTabChip(label: 'Plex', isSelected: true, onSelect: () {}, focusNode: focusNode),
                FocusableTabChip(label: 'Jellyfin', isSelected: false, onSelect: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Color backgroundOf(WidgetTester tester, String label) {
    final container = tester.widget<AnimatedContainer>(
      find.ancestor(of: find.text(label), matching: find.byType(AnimatedContainer)).first,
    );
    return ((container.decoration as BoxDecoration).color)!;
  }

  Color labelColorOf(WidgetTester tester, String label) => tester.widget<Text>(find.text(label)).style!.color!;

  testWidgets('the active tab is marked in the accent, not in the focus colour', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await pumpChips(tester, focusNode: focusNode);

    expect(backgroundOf(tester, 'Plex'), activeTabChipColor);
    expect(labelColorOf(tester, 'Plex'), onActiveTabChipColor);
  });

  testWidgets('an inactive tab keeps its quiet surface', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await pumpChips(tester, focusNode: focusNode);

    expect(backgroundOf(tester, 'Jellyfin'), isNot(activeTabChipColor));
  });

  testWidgets('focus on the active tab keeps the accent visible in the label', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await pumpChips(tester, focusNode: focusNode);
    // A key press is what puts the app into keyboard mode, which is the only
    // mode that paints focus at all.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    focusNode.requestFocus();
    await tester.pumpAndSettle();

    // Focus wins the background, so the eye finds it the same way on every
    // screen; the accent moves into the text rather than disappearing.
    expect(backgroundOf(tester, 'Plex'), isNot(activeTabChipColor));
    expect(labelColorOf(tester, 'Plex'), activeTabChipColor);
  });
}
