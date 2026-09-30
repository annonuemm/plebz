import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/widgets/artwork_dim_scope.dart';
import 'package:plezy/widgets/optimized_media_image.dart';

/// The redesign steps back what does not hold focus by darkening the picture
/// itself. A wash of black over the card's box showed as a translucent dark
/// ground wherever the picture did not fill that box.
void main() {
  // A 1×1 transparent PNG, so the image is drawn from a local file and needs
  // no client.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );
  late File file;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('artwork_dim');
    file = File('${dir.path}/art.png')..writeAsBytesSync(png);
  });

  Future<void> pump(WidgetTester tester, {required bool dimmed, Animation<double>? own}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ArtworkDim(
          dimmed: dimmed,
          amount: 0.22,
          duration: Duration.zero,
          child: OptimizedMediaImage(imagePath: null, localFilePath: file.path, width: 40, height: 60, artworkDim: own),
        ),
      ),
    );
    // The local file is looked up off the frame.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Image image(WidgetTester tester) => tester.widget<Image>(find.byType(Image));

  testWidgets('a dimmed card darkens its picture, and only the picture', (tester) async {
    await pump(tester, dimmed: true);
    expect(image(tester).color!.a, closeTo(0.22, 0.001));
    expect(image(tester).colorBlendMode, BlendMode.srcATop, reason: 'the image\'s own pixels, not a box');
  });

  testWidgets('the card in focus is drawn as it is', (tester) async {
    await pump(tester, dimmed: false);
    expect(image(tester).color, isNull);
  });

  testWidgets('a rail\'s own dim and the card\'s add', (tester) async {
    await pump(tester, dimmed: true, own: const AlwaysStoppedAnimation(0.3));
    expect(image(tester).color!.a, closeTo(0.52, 0.001));
  });
}
