import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/widgets/corner_backdrop.dart';

void main() {
  const boundaryKey = Key('shot');

  Widget stage(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: boundaryKey,
        child: CornerBackdrop(width: 200, height: 100, child: child),
      ),
    ),
  );

  Future<Color> colourAt(WidgetTester tester, double fx, double fy) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      final x = (width * fx).round(), y = (image.height * fy).round();
      image.dispose();
      return data!.buffer.asUint8List().sublist((y * width + x) * 4, (y * width + x) * 4 + 4);
    });
    return Color.fromARGB(bytes![3], bytes[0], bytes[1], bytes[2]);
  }

  /// The colour drawn near the top right, where neither feather reaches.
  Future<Color> colourAtTopRight(WidgetTester tester) => colourAt(tester, 0.9, 0.05);

  testWidgets('the feathered picture is shown as an image, not as live masks', (tester) async {
    await tester.pumpWidget(stage(const ColoredBox(color: Color(0xFFFF0000))));

    expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty);
    expect(await colourAtTopRight(tester), const Color(0xFFFF0000));
  });

  testWidgets('a new picture is drawn anew', (tester) async {
    await tester.pumpWidget(stage(const ColoredBox(color: Color(0xFFFF0000))));
    expect(await colourAtTopRight(tester), const Color(0xFFFF0000));

    await tester.pumpWidget(stage(const ColoredBox(color: Color(0xFF0000FF))));
    expect(await colourAtTopRight(tester), const Color(0xFF0000FF));
  });

  testWidgets('a child with a boundary of its own stays live', (tester) async {
    await tester.pumpWidget(stage(const RepaintBoundary(child: ColoredBox(color: Color(0xFFFF0000)))));

    expect(tester.layers.whereType<ShaderMaskLayer>(), isNotEmpty);
    expect(await colourAtTopRight(tester), const Color(0xFFFF0000));
  });

  testWidgets('the feathers look as they did drawn live', (tester) async {
    const points = [(0.1, 0.5), (0.25, 0.3), (0.5, 0.75), (0.9, 0.9)];
    await tester.pumpWidget(stage(const ColoredBox(color: Color(0xFFFF0000))));
    final asImage = [for (final (x, y) in points) await colourAt(tester, x, y)];
    await tester.pumpWidget(stage(const RepaintBoundary(child: ColoredBox(color: Color(0xFFFF0000)))));
    final live = [for (final (x, y) in points) await colourAt(tester, x, y)];

    for (var i = 0; i < points.length; i++) {
      expect((asImage[i].a - live[i].a).abs(), lessThan(2 / 255), reason: 'at ${points[i]}');
    }
    expect(asImage.first.a, inExclusiveRange(0.05, 0.95), reason: 'the left feather is sampled');
  });

  testWidgets('a page rebuilding round a still picture does not draw it again', (tester) async {
    await tester.pumpWidget(stage(const ColoredBox(color: Color(0xFFFF0000))));
    List<ui.Picture?> pictures() => [for (final layer in tester.layers.whereType<PictureLayer>()) layer.picture];
    final before = pictures();

    await tester.pumpWidget(stage(const ColoredBox(color: Color(0xFFFF0000))));
    final after = pictures();

    expect(after.length, before.length);
    for (var i = 0; i < after.length; i++) {
      expect(identical(after[i], before[i]), isTrue, reason: 'picture $i was recorded again');
    }
  });
}
