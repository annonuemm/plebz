import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/redesign/ocker_status_bar_ground.dart';
import 'package:plezy/services/plebz_prefs.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';
import 'package:plezy/utils/platform_detector.dart';

MonoTokens tokensOf(ThemeData theme) => theme.extension<MonoTokens>()!;

void main() {
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<ScrollController> pumpPage(WidgetTester tester, AppThemeVariant variant) async {
    TvDetectionService.debugSetAppleTVOverride(false);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 30);
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: variant),
        home: Scaffold(
          body: OckerStatusBarGround(
            child: ListView.builder(
              controller: controller,
              itemCount: 50,
              itemBuilder: (_, i) => SizedBox(height: 80, child: Text('row $i')),
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  Finder strip() => find.byWidgetPredicate((w) => w is ColoredBox && w.color.a > 0);

  testWidgets('under the redesign the status bar takes the ground once the page has scrolled', (tester) async {
    final controller = await pumpPage(tester, AppThemeVariant.glas);
    expect(strip(), findsNothing, reason: 'at the top the ground shows through');

    controller.jumpTo(40);
    await tester.pump();
    expect(tester.widget<ColoredBox>(strip()).color.a, closeTo(0.5, 0.01), reason: 'fading in');

    controller.jumpTo(400);
    await tester.pump();
    final colour = tester.widget<ColoredBox>(strip()).color;
    expect(colour, tokensOf(monoTheme(dark: true, variant: AppThemeVariant.glas)).bg.withValues(alpha: 1));
    expect(tester.getSize(strip()).height, 30, reason: 'the status bar, no more');
  });

  testWidgets('the original look is left as it was', (tester) async {
    final controller = await pumpPage(tester, AppThemeVariant.standard);
    controller.jumpTo(400);
    await tester.pump();

    expect(find.descendant(of: find.byType(OckerStatusBarGround), matching: find.byType(Stack)), findsNothing);
  });
}
