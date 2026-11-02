import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focus_theme.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/redesign/ocker_type.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';

ThemeData _v2() => monoTheme(MonoPalette.dark, variant: AppThemeVariant.glasV2);
ThemeData _glas() => monoTheme(MonoPalette.dark, variant: AppThemeVariant.glas);

void main() {
  test('Glas – v2 is Glas in its paint and palette, with its own rulebook flag', () {
    expect(isRedesignVariant(AppThemeVariant.glasV2), isTrue);
    expect(isGlasVariant(AppThemeVariant.glasV2), isTrue);
    expect(isGlasVariant(AppThemeVariant.flach), isFalse);
    final v2 = _v2().extension<MonoTokens>()!;
    final glas = _glas().extension<MonoTokens>()!;
    expect(v2.glass, isTrue);
    expect(v2.flat, isFalse);
    expect(v2.v2, isTrue);
    expect(glas.v2, isFalse);
    expect(v2.bg, glas.bg, reason: "Glas's palette");
    expect(v2.accent, glas.accent);
    expect(offeredAppThemeVariants, contains(AppThemeVariant.glasV2));
  });

  test('the stored name reads back, appended after the others', () {
    expect(AppThemeVariant.values.last, AppThemeVariant.glasV2);
    expect(AppThemeVariant.values.byName('glasV2'), AppThemeVariant.glasV2);
  });

  test('type is set on one ramp: the nearest step, the smaller one on a tie', () {
    expect(OckerType.onRamp(18), 18);
    expect(OckerType.onRamp(19), 18);
    expect(OckerType.onRamp(21), 22);
    expect(OckerType.onRamp(23), 22);
    expect(OckerType.onRamp(25), 22, reason: 'a tie between 22 and 28 takes the smaller');
    expect(OckerType.onRamp(27), 28);
    expect(OckerType.onRamp(13), 12);
    expect(OckerType.onRamp(50), 48);

    const plain = OckerType(1);
    const ramped = OckerType(1, ramp: true);
    expect(plain.spotlightSynopsis.fontSize, 25);
    expect(ramped.spotlightSynopsis.fontSize, 25, reason: 'stays Glas\'s size: 22 read small from the sofa');
    expect(ramped.spotlightFacts.fontSize, 22);
    expect(ramped.body.fontSize, 18);
    final sizes = {
      for (final style in [
        ramped.body,
        ramped.secondary,
        ramped.metadata,
        ramped.synopsis,
        ramped.sectionHeading,
        ramped.counter,
        ramped.clock,
        ramped.primaryButton,
        ramped.guideSummary,
      ])
        style.fontSize,
    };
    expect(sizes.every(OckerType.v2Ramp.contains), isTrue, reason: '$sizes');
    // Only sizes: a title's tight tracking taken to the ramp spaced it out.
    expect(ramped.detailTitle().letterSpacing, plain.detailTitle().letterSpacing);
    expect(ramped.titleBoxHeight(), plain.titleBoxHeight());
  });

  testWidgets('a picture grows as under Glas: the gap of the grid is drawn for that growth', (tester) async {
    late double v2Scale;
    await tester.pumpWidget(
      Theme(
        data: _v2(),
        child: Builder(
          builder: (context) {
            v2Scale = FocusTheme.posterFocusScaleFor(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(v2Scale, FocusTheme.flatPosterFocusScale);
  });

  testWidgets('what is chosen is a flat wash of the accent, never glass with a lit edge', (tester) async {
    Future<void> pump(ThemeData theme, {required bool bright}) => tester.pumpWidget(
      Theme(
        data: theme,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 120,
              height: 40,
              child: OckerGlassFocusFill(shape: const StadiumBorder(), bright: bright, tint: 1),
            ),
          ),
        ),
      ),
    );
    bool litEdge() =>
        tester.widgetList<CustomPaint>(find.byType(CustomPaint)).any((paint) => paint.foregroundPainter != null);

    await pump(_v2(), bright: false);
    expect(litEdge(), isFalse);
    final wash = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<ShapeDecoration>()
        .single;
    final accent = _v2().extension<MonoTokens>()!.accent;
    expect(wash.color, accent.withValues(alpha: ockerV2ChosenWash));

    Iterable<Color?> fills() => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<ShapeDecoration>()
        .map((decoration) => decoration.color);
    await pump(_v2(), bright: true);
    expect(fills(), isNot(contains(accent.withValues(alpha: ockerV2ChosenWash))), reason: 'focus is not the wash');
    await pump(_glas(), bright: false);
    expect(
      fills(),
      isNot(contains(_glas().extension<MonoTokens>()!.accent.withValues(alpha: ockerV2ChosenWash))),
      reason: 'Glas itself keeps its quiet capsule',
    );
  });

  testWidgets('a switch that is on wears the accent under v2', (tester) async {
    final theme = _v2();
    final track = theme.switchTheme.trackColor!.resolve({WidgetState.selected});
    expect(track, theme.extension<MonoTokens>()!.accent);
    expect(theme.switchTheme.thumbColor!.resolve({WidgetState.selected}), Colors.white);
    expect(_glas().switchTheme.trackColor, isNull);
  });
}
