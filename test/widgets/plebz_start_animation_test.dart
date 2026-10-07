import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/plebz_start_animation.dart';

Widget _host({required GlobalKey<PlebzStartAnimationState> key, bool still = false, bool stacked = false}) =>
    MediaQuery(
      data: MediaQueryData(size: const Size(960, 540), disableAnimations: still),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: PlebzStartAnimation(key: key, markHeight: 108, stacked: stacked),
          ),
        ),
      ),
    );

void main() {
  testWidgets('the entrance ends once the name is out, then the logo can step back', (tester) async {
    final key = GlobalKey<PlebzStartAnimationState>();
    await tester.pumpWidget(_host(key: key));

    var introDone = false;
    unawaited(key.currentState!.introDone.then((_) => introDone = true));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(introDone, isFalse, reason: 'still drawing');

    await tester.pump(PlebzStartAnimationState.introDuration);
    expect(introDone, isTrue);
    // The connecting sheen keeps running until the logo leaves.
    expect(tester.hasRunningAnimations, isTrue);

    var left = false;
    unawaited(key.currentState!.leave().then((_) => left = true));
    await tester.pump();
    await tester.pump(PlebzStartAnimationState.leaveDuration + const Duration(milliseconds: 50));
    await tester.pump();
    expect(left, isTrue);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('with animations switched off it stands still and leaves at once', (tester) async {
    final key = GlobalKey<PlebzStartAnimationState>();
    await tester.pumpWidget(_host(key: key, still: true));

    var introDone = false;
    unawaited(key.currentState!.introDone.then((_) => introDone = true));
    await tester.pump();
    expect(introDone, isTrue);
    expect(tester.hasRunningAnimations, isFalse);

    var left = false;
    unawaited(key.currentState!.leave().then((_) => left = true));
    await tester.pump();
    expect(left, isTrue);
  });

  testWidgets('portrait puts the name under the mark', (tester) async {
    final key = GlobalKey<PlebzStartAnimationState>();
    await tester.pumpWidget(_host(key: key, stacked: true));
    await tester.pump(PlebzStartAnimationState.introDuration);

    final name = tester.getRect(find.byType(Image));
    final mark = tester.getRect(find.byType(CustomPaint).last);
    expect(name.top, greaterThan(mark.bottom));
    expect(PlebzStartAnimation.heightFor(108, stacked: true), greaterThan(108));
  });

  testWidgets('the mark takes the Glas accent; the Plebz palette and the original look keep the logo', (tester) async {
    Future<List<Color>> coloursIn(ThemeData theme) async {
      late List<Color> colours;
      await tester.pumpWidget(
        Theme(
          data: theme,
          child: Builder(
            builder: (context) {
              colours = plebzMarkColours(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return colours;
    }

    for (final accent in GlasAccent.values) {
      final colours = await coloursIn(monoTheme(dark: true, variant: AppThemeVariant.glas, glasAccent: accent));
      if (accent == GlasAccent.plebz) {
        expect(colours, plebzLogoColours);
      } else {
        expect(colours, hasLength(3), reason: accent.name);
        expect(colours[1], glasPalette(accent).accent, reason: accent.name);
      }
    }
    expect(await coloursIn(monoTheme(dark: true)), plebzLogoColours);
  });
}
