import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/redesign/ocker_play_ground.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';

/// The one main action's ground (Plebz): under Flach one flat fill of the
/// accent, as Apple's buttons are — the gradient from the mark is gone, on
/// the television as everywhere (the user's call, 2026-11-03).
void main() {
  Future<BuildContext> pump(WidgetTester tester, {required Color accent}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark, variant: AppThemeVariant.flach, flachAccent: accent),
        home: const Scaffold(
          body: Center(
            child: OckerPlayGround(
              v2: false,
              focused: false,
              shape: StadiumBorder(),
              radius: 22,
              child: SizedBox(width: 160, height: 44),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    return tester.element(find.byType(OckerPlayGround));
  }

  ShapeDecoration ground(WidgetTester tester) => tester
      .widgetList<DecoratedBox>(find.descendant(of: find.byType(OckerPlayGround), matching: find.byType(DecoratedBox)))
      .map((box) => box.decoration)
      .whereType<ShapeDecoration>()
      .first;

  testWidgets('Flach: the accent in one flat fill, no gradient and no glow', (tester) async {
    final context = await pump(tester, accent: const Color(0xFF1D9E75));

    final decoration = ground(tester);
    expect(decoration.gradient, isNull);
    expect(decoration.color, tokens(context).accent);
    expect(decoration.shadows, isNull);
  });

  testWidgets('Flach: white on a dark accent, the ground on a light one', (tester) async {
    var context = await pump(tester, accent: const Color(0xFF185FA5));
    expect(OckerPlayGround.foreground(context, v2: false), Colors.white);

    context = await pump(tester, accent: const Color(0xFFF5D547));
    expect(OckerPlayGround.foreground(context, v2: false), tokens(context).bg);
  });
}
