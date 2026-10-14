import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/providers/theme_provider.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/device_performance.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/liquid_glass.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';

import '../test_helpers/prefs.dart';

/// "Liquid Glass" under "Redesign – Glas" (fork option): the menus and the
/// side rail lie over the picture behind them frosted and bent at the rim, on
/// a lighter ground; off by default, only in the Apple builds, never on the
/// reduced tier. Tests run without Impeller, so they see the blur that stands
/// in for the lens.
void main() {
  // An Apple build, unless a test says otherwise.
  setUp(() => OckerLiquidGlass.debugOfferedHere = true);
  tearDown(() {
    OckerLiquidGlass.setting.value = false;
    OckerLiquidGlass.fakeGlass.value = true;
    OckerLiquidGlass.debugOfferedHere = null;
    DevicePerformance.debugReset();
  });

  Future<void> pumpPane(WidgetTester tester, {AppThemeVariant variant = AppThemeVariant.glas, bool liquid = true}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: variant),
          home: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: OckerGlass(
                borderRadius: const BorderRadius.all(Radius.circular(18)),
                liquid: liquid,
                child: const SizedBox.expand(key: Key('words')),
              ),
            ),
          ),
        ),
      );

  Finder blurBehindWords() => find.ancestor(of: find.byKey(const Key('words')), matching: find.byType(BackdropFilter));

  double groundAlpha(WidgetTester tester) => tester
      .widgetList<DecoratedBox>(find.ancestor(of: find.byKey(const Key('words')), matching: find.byType(DecoratedBox)))
      .map((box) => box.decoration as BoxDecoration)
      .firstWhere((d) => d.color != null && d.gradient == null)
      .color!
      .a;

  // The glass's sheen: what a flat surface goes without. Only the pane's own
  // boxes; the page's ground above it has gradients of its own.
  bool sheen(WidgetTester tester) => tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(OckerGlass),
          matching: find.ancestor(of: find.byKey(const Key('words')), matching: find.byType(DecoratedBox)),
        ),
      )
      .any((box) => (box.decoration as BoxDecoration).gradient != null);

  // Plebz (the user's call, 2026-10-13): under Glas the panes that turn to
  // Liquid Glass — the navigation, the menus, the sheets — are flat while it
  // is off on Apple's builds, in exactly the same shape.
  void expectFlat(WidgetTester tester) {
    expect(find.byType(BackdropFilter), findsNothing);
    expect(sheen(tester), isFalse, reason: 'no sheen');
    expect(groundAlpha(tester), 1, reason: 'one solid surface');
    final ground = tester
        .widgetList<DecoratedBox>(
          find.ancestor(of: find.byKey(const Key('words')), matching: find.byType(DecoratedBox)),
        )
        .map((box) => box.decoration as BoxDecoration)
        .firstWhere((d) => d.color != null);
    expect(ground.borderRadius, const BorderRadius.all(Radius.circular(18)), reason: 'the same shape');
  }

  testWidgets('a liquid pane is flat while Liquid Glass is off, in the same shape', (tester) async {
    await pumpPane(tester);

    expectFlat(tester);
  });

  testWidgets('a pane that never turns liquid stays plain glass', (tester) async {
    await pumpPane(tester, liquid: false);

    expect(find.byType(BackdropFilter), findsNothing);
    expect(sheen(tester), isTrue);
    expect(groundAlpha(tester), closeTo(ockerReadingGroundOpacity, 0.01));
  });

  testWidgets('liquid glass blurs behind the pane, on a lighter ground, and follows the switch', (tester) async {
    await pumpPane(tester);

    OckerLiquidGlass.setting.value = true;
    await tester.pump();
    expect(blurBehindWords(), findsOneWidget);
    expect(
      groundAlpha(tester),
      closeTo(ockerReadingGroundOpacity * OckerLiquidGlass.groundFactor, 0.01),
      reason: 'the blur does part of what the ground did',
    );

    OckerLiquidGlass.setting.value = false;
    await tester.pump();
    expectFlat(tester);
  });

  testWidgets('never on the reduced tier, whatever the switch says', (tester) async {
    DevicePerformance.debugReset(override: VisualEffectsSetting.reduced);
    OckerLiquidGlass.setting.value = true;
    await pumpPane(tester);

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('never in the APK: an Android build ignores the switch and wears the fake glass for good', (
    tester,
  ) async {
    OckerLiquidGlass.debugOfferedHere = false;
    OckerLiquidGlass.setting.value = true;
    await pumpPane(tester);

    expect(OckerLiquidGlass.offerable, isFalse);
    expect(find.byType(BackdropFilter), findsNothing, reason: 'no lens, even from a Mac backup');
    expect(sheen(tester), isTrue, reason: 'the fake glass stands in for the lens');
    expect(groundAlpha(tester), closeTo(ockerReadingGroundOpacity, 0.01), reason: 'nothing behind shows through sharp');
    // Lighter than the plain glass: a frost of white over the ground, as
    // Apple's glass gets from the picture behind it (the user's call).
    final tk = monoTheme(dark: true, variant: AppThemeVariant.glas).extension<MonoTokens>()!;
    final ground = tester
        .widgetList<DecoratedBox>(
          find.ancestor(of: find.byKey(const Key('words')), matching: find.byType(DecoratedBox)),
        )
        .map((box) => box.decoration as BoxDecoration)
        .firstWhere((d) => d.color != null && d.gradient == null)
        .color!;
    expect(ground.computeLuminance(), greaterThan(tk.bg.computeLuminance()));

    OckerLiquidGlass.setting.value = false;
    await tester.pump();
    expect(sheen(tester), isTrue, reason: 'whatever the switch says');
  });

  testWidgets('on Android the fake glass can be switched off: flat, as Apple\'s builds without Liquid Glass', (
    tester,
  ) async {
    OckerLiquidGlass.debugOfferedHere = false;
    await pumpPane(tester);
    expect(sheen(tester), isTrue);

    OckerLiquidGlass.fakeGlass.value = false;
    await tester.pump();
    expectFlat(tester);

    OckerLiquidGlass.fakeGlass.value = true;
    await tester.pump();
    expect(sheen(tester), isTrue, reason: 'back at once, without a rebuild from above');
  });

  testWidgets('the fake glass switch leaves Apple\'s builds alone', (tester) async {
    OckerLiquidGlass.fakeGlass.value = false;
    OckerLiquidGlass.setting.value = true;
    await pumpPane(tester);
    expect(blurBehindWords(), findsOneWidget, reason: 'Liquid Glass is theirs');
  });

  testWidgets('Flach stays flat', (tester) async {
    OckerLiquidGlass.setting.value = true;
    await pumpPane(tester, variant: AppThemeVariant.flach);

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('only the panes that ask are liquid; a band has no ground under Glas, liquid or not', (tester) async {
    OckerLiquidGlass.setting.value = true;
    await pumpPane(tester, liquid: false);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(groundAlpha(tester), closeTo(ockerReadingGroundOpacity, 0.01));

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: const Center(
          child: OckerGlassBand(overhang: EdgeInsets.all(6), child: Text('Filme')),
        ),
      ),
    );
    bool ground(Widget w) =>
        (w is DecoratedBox && w.decoration is ShapeDecoration) ||
        (w is CustomPaint && w.foregroundPainter != null && w.child is DecoratedBox);
    expect(find.byType(BackdropFilter), findsNothing, reason: 'tabs, filters and the detail buttons are no glass');
    expect(find.byWidgetPredicate(ground), findsNothing, reason: 'no track, no pane');

    OckerLiquidGlass.setting.value = false;
    await tester.pump();
    expect(find.byWidgetPredicate(ground), findsNothing);
  });

  testWidgets('a focused poster wears no rim: Glas rings a picture in white', (tester) async {
    OckerLiquidGlass.setting.value = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: const Center(
          child: SizedBox(
            width: 120,
            height: 180,
            child: OckerLiquidFocusRim(focused: true, radii: BorderRadius.all(Radius.circular(14))),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.descendant(of: find.byType(OckerLiquidFocusRim), matching: find.byType(CustomPaint)), findsNothing);
  });

  group('the provider', () {
    setUp(() {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
    });

    test('keeps the switch in step with the setting', () async {
      final service = await SettingsService.getInstance();
      final provider = ThemeProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(OckerLiquidGlass.setting.value, isFalse, reason: 'off by default');

      await service.write(PlebzPrefs.glasLiquid, true);
      await Future<void>.delayed(Duration.zero);
      expect(OckerLiquidGlass.setting.value, isTrue);

      await service.write(PlebzPrefs.glasLiquid, false);
      await Future<void>.delayed(Duration.zero);
      expect(OckerLiquidGlass.setting.value, isFalse);

      expect(OckerLiquidGlass.fakeGlass.value, isTrue, reason: 'the fake glass on by default');
      await service.write(PlebzPrefs.glasFakeGlass, false);
      await Future<void>.delayed(Duration.zero);
      expect(OckerLiquidGlass.fakeGlass.value, isFalse);
    });
  });

  test('the lens follows the shape it lies in', () {
    final tk = monoTheme(dark: true, variant: AppThemeVariant.glas).extension<MonoTokens>()!;
    expect(tk.glass, isTrue);
    expect(
      OckerLiquidGlass.lensThickness,
      greaterThan(OckerLiquidGlass.lensStrength),
      reason: 'bends within its bevel',
    );
    expect(OckerLiquidGlass.groundFactor, inInclusiveRange(0.3, 1.0));
    expect(OckerLiquidGlass.rimThickness, greaterThan(OckerLiquidGlass.rimStrength));
  });
}
