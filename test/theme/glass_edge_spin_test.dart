import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focus_theme.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant;
import 'package:plezy/theme/glass_edge_spin.dart';
import 'package:plezy/theme/glass_focus_decoration.dart';
import 'package:plezy/theme/mono_theme.dart';

void main() {
  final spin = GlassEdgeSpin.instance;
  tearDown(spin.debugReset);

  /// A glass focus edge, showing or at rest, and nothing else on screen.
  Future<void> pumpEdge(WidgetTester tester, {bool focused = true, bool shown = true}) => tester.pumpWidget(
    MaterialApp(
      theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
      home: Center(
        child: Offstage(
          offstage: !shown,
          child: Builder(
            builder: (context) => DecoratedBox(
              decoration: FocusTheme.focusDecoration(context, isFocused: focused),
              child: const SizedBox(width: 120, height: 180),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('stands still while switched off', (tester) async {
    await pumpEdge(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(spin.turn, 0);
    expect(spin.isTicking, isFalse);
  });

  testWidgets('turns once round in seven seconds, and keeps turning while the edge paints', (tester) async {
    spin.enabled = true;
    await pumpEdge(tester);
    expect(spin.isTicking, isTrue);

    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // 1.75 s of turning at one turn in seven seconds.
    expect(spin.turn, closeTo(0.25, 0.02));
    spin.enabled = false;
  });

  testWidgets('an edge at rest never starts it', (tester) async {
    spin.enabled = true;
    await pumpEdge(tester, focused: false);
    await tester.pump(const Duration(milliseconds: 100));

    expect(spin.isTicking, isFalse);
    expect(spin.turn, 0);
  });

  testWidgets('stops once no edge is painted — under the player, say — and starts again with the next', (tester) async {
    spin.enabled = true;
    await pumpEdge(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(spin.isTicking, isTrue);

    await pumpEdge(tester, shown: false);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(spin.isTicking, isFalse, reason: 'mounted but not painted: no frames for it');

    await pumpEdge(tester);
    expect(spin.isTicking, isTrue);
    spin.enabled = false;
  });

  testWidgets('holds still while keys come, and turns on once they are quiet', (tester) async {
    spin.enabled = true;
    await pumpEdge(tester);
    await tester.pump(const Duration(milliseconds: 500));
    final before = spin.turn;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(spin.turn, closeTo(before, 0.01), reason: 'within the settle time of the press');

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(spin.turn, greaterThan(before + 0.05), reason: 'turning again after the keys went quiet');
    spin.enabled = false;
  });

  testWidgets('switched off, every edge goes back to rest', (tester) async {
    spin.enabled = true;
    await pumpEdge(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(spin.turn, greaterThan(0));

    spin.enabled = false;
    await tester.pump();
    expect(spin.turn, 0);
    expect(spin.isTicking, isFalse);
  });

  test('the edge is the same colours whatever the turn', () {
    // The turn moves where the colours fall, not what they are: the decoration
    // stays equal, so no focus animation restarts because of it.
    final a = GlassFocusDecoration(
      colors: const GlassEdgeColors(lit: Colors.white, mid: Colors.black, end: Colors.red, midFrom: 0.3, midTo: 0.55),
      opacity: 1,
      ringWidth: 1,
    );
    final b = GlassFocusDecoration(
      colors: const GlassEdgeColors(lit: Colors.white, mid: Colors.black, end: Colors.red, midFrom: 0.3, midTo: 0.55),
      opacity: 1,
      ringWidth: 1,
    );
    expect(a, b);
  });
}
