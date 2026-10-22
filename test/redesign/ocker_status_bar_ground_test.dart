import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/redesign/ocker_glas_look.dart';
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
        theme: monoTheme(MonoPalette.dark, variant: variant),
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

  testWidgets('under Glas the ground under the status bar fades out softly below it (Plebz)', (tester) async {
    final controller = await pumpPage(tester, AppThemeVariant.glas);
    controller.jumpTo(400);
    await tester.pump();
    final soft = find.descendant(of: find.byType(OckerStatusBarGround), matching: find.byType(DecoratedBox));
    expect(soft, findsOneWidget);
    final gradient = (tester.widget<DecoratedBox>(soft).decoration as BoxDecoration).gradient! as LinearGradient;
    expect(gradient.colors.last.a, 0, reason: 'fading out at its foot');
    expect(tester.getSize(soft).height, 30 + OckerScrollEdge.fade, reason: 'the status bar and the fade below it');
  });

  testWidgets('under Flach the status bar takes the ground once the page has scrolled', (tester) async {
    final controller = await pumpPage(tester, AppThemeVariant.flach);
    expect(strip(), findsNothing, reason: 'at the top the ground shows through');

    controller.jumpTo(40);
    await tester.pump();
    expect(tester.widget<ColoredBox>(strip()).color.a, closeTo(0.5, 0.01), reason: 'fading in');

    controller.jumpTo(400);
    await tester.pump();
    final colour = tester.widget<ColoredBox>(strip()).color;
    expect(colour, tokensOf(monoTheme(MonoPalette.dark, variant: AppThemeVariant.flach)).bg.withValues(alpha: 1));
    expect(tester.getSize(strip()).height, 30, reason: 'the status bar, no more');
  });

  testWidgets('the original look is left as it was', (tester) async {
    final controller = await pumpPage(tester, AppThemeVariant.standard);
    controller.jumpTo(400);
    await tester.pump();

    expect(find.descendant(of: find.byType(OckerStatusBarGround), matching: find.byType(Stack)), findsNothing);
  });
}
