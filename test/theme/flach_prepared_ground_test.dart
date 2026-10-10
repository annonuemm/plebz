import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant;
import 'package:plezy/theme/glass_backdrop.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';

/// Flach's ground and its lights come as one picture prepared once, instead
/// of full-screen gradients worked out on every frame — which made page fades
/// stutter on a television. It has to look the same as before.
void main() {
  setUp(PreparedGrounds.debugReset);
  tearDown(PreparedGrounds.debugReset);

  MonoTokens flach({Color? plain}) =>
      monoTheme(dark: true, variant: AppThemeVariant.flach, plainGround: plain).extension<MonoTokens>()!;

  Future<Uint8List> pixelsOf(WidgetTester tester, Widget ground) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 320, height: 180, child: ground),
          ),
        ),
      ),
    );
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final data = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes;
    });
    return data!.buffer.asUint8List();
  }

  testWidgets('the prepared ground looks as the gradients drawn live did', (tester) async {
    final tk = flach();
    final glows = flachGroundGlows(tk);
    expect(glows, isNotEmpty);

    final live = await pixelsOf(
      tester,
      ColoredBox(
        color: tk.bg,
        child: Stack(
          fit: StackFit.expand,
          children: [for (final glow in glows) DecoratedBox(decoration: BoxDecoration(gradient: glow))],
        ),
      ),
    );
    final prepared = await pixelsOf(tester, FlachGroundGlow(glows: glows, ground: tk.bg));

    expect(prepared.length, live.length);
    var largest = 0;
    for (var i = 0; i < live.length; i++) {
      final difference = (live[i] - prepared[i]).abs();
      if (difference > largest) largest = difference;
    }
    expect(largest, lessThanOrEqualTo(2), reason: 'no more than the dither of a gradient');
  });

  testWidgets('a ground is prepared once and reused on every page and frame after', (tester) async {
    final theme = monoTheme(dark: true, variant: AppThemeVariant.flach);
    Widget page(String name) => MaterialApp(
      theme: theme,
      home: GlassBackdrop(child: Text(name)),
    );

    await tester.pumpWidget(page('Start'));
    expect(PreparedGrounds.debugPrepared, 1);

    await tester.pumpWidget(page('Bibliothek'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(PreparedGrounds.debugPrepared, 1, reason: 'same size, same lights');
  });

  testWidgets('a plain ground has no lights and prepares nothing', (tester) async {
    final theme = monoTheme(dark: true, variant: AppThemeVariant.flach, plainGround: redesignOffBlackGround);
    expect(flachGroundGlows(flach(plain: redesignOffBlackGround)), isEmpty);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const GlassBackdrop(child: Text('Start')),
      ),
    );

    expect(PreparedGrounds.debugPrepared, 0);
  });

  testWidgets('a tap on the bare ground stops there, as on the plain fill before', (tester) async {
    var under = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.flach),
        home: Stack(
          children: [
            Positioned.fill(child: GestureDetector(onTap: () => under++)),
            const GlassBackdrop(child: SizedBox.shrink()),
          ],
        ),
      ),
    );

    await tester.tapAt(const Offset(200, 200));
    expect(under, 0);
  });
}
