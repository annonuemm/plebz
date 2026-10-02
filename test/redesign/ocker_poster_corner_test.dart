import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';

/// §10 asked for no corners anywhere. Artwork broke the rule first — a poster
/// is not a box the interface drew but a picture it is showing — and the boxes
/// followed, because a square one beside a rounded picture read as the thing
/// that had been forgotten. What is left of the rule is the proportion.
void main() {
  test('a poster keeps the same corner at every size it is drawn', () {
    // The shelf poster at 1920, the same shelf on a 720p television, and the
    // thumbnails in the hero banner's strip, which are two thirds of those.
    expect(ockerPosterCorner(240).topLeft.x, closeTo(15.6, 0.01));
    expect(ockerPosterCorner(173).topLeft.x, closeTo(11.25, 0.01));
    expect(ockerPosterCorner(122).topLeft.x, closeTo(7.93, 0.01));

    // Proportional, so the shape is the same shape wherever it is drawn.
    expect(ockerPosterCorner(240).topLeft.x / 240, closeTo(ockerPosterCorner(122).topLeft.x / 122, 0.0001));

    // And bounded at both ends: under four pixels a corner is a smudge, past
    // twenty-two a poster starts reading as a lozenge.
    expect(ockerPosterCorner(10).topLeft.x, 4);
    expect(ockerPosterCorner(2000).topLeft.x, 22);
    expect(ockerPosterCorner(double.infinity).topLeft.x, 12, reason: 'a cell that measures itself still gets one');
  });

  testWidgets('the whole redesign rounds, and the pictures a shade more', (tester) async {
    for (final variant in AppThemeVariant.values) {
      late double artwork;
      late double flat;
      late bool square;
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: variant),
          home: Builder(
            builder: (context) {
              artwork = artworkRadius(context);
              flat = flatRadius(context, 12);
              square = tokens(context).squareCorners;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Settled, not pumped: MaterialApp cross-fades one theme into the next,
      // and a single frame after the switch reads a half-way house.
      await tester.pumpAndSettle();

      expect(square, isFalse, reason: '$variant draws no square corners any more');
      expect(flat, 12, reason: '$variant lets every box keep the corner it asked for');
      if (variant == AppThemeVariant.standard) {
        expect(artwork, tokens(tester.element(find.byType(SizedBox).first)).radiusSm, reason: '$variant is untouched');
        continue;
      }
      // A picture is drawn a shade rounder than the boxes around it — which is
      // what a poster's own 6.5 % corner comes out at.
      expect(artwork, greaterThan(0), reason: '$variant rounds the pictures');
    }
  });
}
