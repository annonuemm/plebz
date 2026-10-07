import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';

Future<bool> _wearsGradient(WidgetTester tester, ThemeData theme) async {
  late bool wears;
  await tester.pumpWidget(
    Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          wears = ockerPlebzPlay(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return wears;
}

void main() {
  testWidgets('only the Plebz palette puts the logo\'s gradient on the play buttons, OLED or not', (tester) async {
    for (final accent in GlasAccent.values) {
      for (final oled in [false, true]) {
        final theme = monoTheme(dark: true, oled: oled, variant: AppThemeVariant.glas, glasAccent: accent);
        expect(await _wearsGradient(tester, theme), accent == GlasAccent.plebz, reason: '${accent.name} oled=$oled');
      }
    }
    expect(await _wearsGradient(tester, monoTheme(dark: true)), isFalse, reason: 'the original look');
  });

  test('the Plebz palette is a near-black with the logo\'s violet, and its own', () {
    final plebz = glasPalette(GlasAccent.plebz);
    expect(plebz.accent, const Color(0xFFA866EE));
    expect(plebz.bg.computeLuminance(), lessThan(0.005));
    for (final other in GlasAccent.values.where((a) => a != GlasAccent.plebz)) {
      expect(glasPalette(other).accent, isNot(plebz.accent), reason: other.name);
    }
  });

  testWidgets('the play button is glass tinted with the logo, the page showing through', (tester) async {
    Future<void> pump({required bool focused}) => tester.pumpWidget(
      Theme(
        data: monoTheme(dark: true, variant: AppThemeVariant.glas, glasAccent: GlasAccent.plebz),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: OckerPlebzPlayGround(focused: focused, child: const SizedBox(width: 160, height: 56)),
          ),
        ),
      ),
    );
    LinearGradient tint() {
      final boxes = tester.widgetList<DecoratedBox>(
        find.descendant(of: find.byType(OckerPlebzPlayGround), matching: find.byType(DecoratedBox)),
      );
      return boxes
          .map((box) => box.decoration)
          .whereType<ShapeDecoration>()
          .map((decoration) => decoration.gradient)
          .whereType<LinearGradient>()
          .firstWhere((gradient) => gradient.colors.first.b > 0.9);
    }

    await pump(focused: false);
    expect(tint().colors.first.a, closeTo(OckerPlebzPlayGround.restingTint, 0.01));
    expect(find.descendant(of: find.byType(OckerPlebzPlayGround), matching: find.byType(CustomPaint)), findsWidgets);

    await pump(focused: true);
    expect(tint().colors.first.a, closeTo(OckerPlebzPlayGround.focusedTint, 0.01));
  });
}
