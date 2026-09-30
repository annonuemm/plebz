import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant;
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';
import 'package:plezy/widgets/focusable_list_tile.dart';
import 'package:plezy/widgets/settings_section.dart';

void main() {
  testWidgets('switch tile toggles once from SELECT', (tester) async {
    final focusNode = FocusNode(debugLabel: 'switch');
    addTearDown(focusNode.dispose);
    var value = false;
    var changes = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FocusableSwitchListTile(
              focusNode: focusNode,
              value: value,
              title: const Text('Switch'),
              onChanged: (next) {
                changes++;
                setState(() => value = next);
              },
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(value, isTrue);
    expect(changes, 1);
  });

  testWidgets('checkbox tile toggles once from SELECT', (tester) async {
    final focusNode = FocusNode(debugLabel: 'checkbox');
    addTearDown(focusNode.dispose);
    var value = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FocusableCheckboxListTile(
              focusNode: focusNode,
              value: value,
              title: const Text('Checkbox'),
              onChanged: (next) => setState(() => value = next ?? false),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(value, isTrue);
  });

  testWidgets('disabled switch tile cannot be focused or activated', (tester) async {
    final focusNode = FocusNode(debugLabel: 'disabled switch');
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusableSwitchListTile(
            focusNode: focusNode,
            value: false,
            title: const Text('Disabled'),
            onChanged: null,
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    expect(focusNode.hasFocus, isFalse);
  });

  Widget buildScrollableTiles({required ScrollController controller, required FocusNode bottomNode}) {
    return InputModeTracker(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: Column(
              children: [
                for (var i = 0; i < 30; i++) const SizedBox(height: 56, width: 100),
                FocusableListTile(focusNode: bottomNode, title: const Text('Target'), onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('pointer-mode focus gain does not reveal the tile', (tester) async {
    final bottomNode = FocusNode(debugLabel: 'tile');
    final controller = ScrollController();
    addTearDown(bottomNode.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildScrollableTiles(controller: controller, bottomNode: bottomNode));

    // Programmatic focus without a keyboard session (e.g. a context menu
    // restoring focus on close, issue #2031) must not move the viewport.
    bottomNode.requestFocus();
    await tester.pumpAndSettle();

    expect(bottomNode.hasFocus, isTrue);
    expect(controller.offset, 0);
  });

  testWidgets('keyboard-mode focus gain centers the tile', (tester) async {
    final bottomNode = FocusNode(debugLabel: 'tile');
    final controller = ScrollController();
    addTearDown(bottomNode.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildScrollableTiles(controller: controller, bottomNode: bottomNode));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    bottomNode.requestFocus();
    await tester.pumpAndSettle();

    expect(bottomNode.hasFocus, isTrue);
    expect(controller.offset, greaterThan(0));
  });

  testWidgets('in the redesign the focus ring takes the corners of the card the row fills', (tester) async {
    // A ring with a smaller corner than its card was cut off by the card's
    // clip, leaving four lines with gaps at the corners.
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      InputModeTracker(
        child: MaterialApp(
          theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
          home: Scaffold(
            body: SettingsGroup(
              children: [FocusableListTile(focusNode: node, title: const Text('Sprache'), onTap: () {})],
            ),
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    final ring = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: find.byType(FocusableListTile), matching: find.byType(DecoratedBox)),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.border != null);
    final context = tester.element(find.byType(FocusableListTile));
    expect(ring.borderRadius, groupItemRadii(context, 0, 1));
  });

  testWidgets('in the redesign a switch row marks focus as every other row does, not with Material\'s plate', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      InputModeTracker(
        child: MaterialApp(
          theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
          home: Scaffold(
            body: SettingsGroup(
              children: [
                FocusableSwitchListTile(
                  focusNode: node,
                  title: const Text('Untertitel'),
                  value: true,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    final ring = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: find.byType(FocusableSwitchListTile), matching: find.byType(DecoratedBox)),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .where((decoration) => decoration.border != null);
    expect(ring, isNotEmpty, reason: 'the ring of the card\'s rows');
    final switchContext = tester.element(find.byType(SwitchListTile));
    expect(Theme.of(switchContext).focusColor, Colors.transparent, reason: 'no plate, no halo round the thumb');
  });
}
