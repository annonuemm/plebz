import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/redesign/ocker_type.dart';

/// A title's description is shown in two places — the panel at the left of a
/// page, and the backdrop a focused row unfolds into. They are the same
/// sentence about the same thing, so they are set at the same size; the two
/// drifted apart once already, when the backdrop was given a step up for
/// legibility and the panel was not.
void main() {
  group('Reading size', () {
    test('is one step above the interface around it', () {
      const type = OckerType(1);
      expect(type.synopsis.fontSize, greaterThan(type.body.fontSize!));
      expect(type.synopsis.fontSize! / type.body.fontSize!, closeTo(OckerType.readingScale, 0.001));
      // Prose keeps the generous leading; only the size moves.
      expect(type.synopsis.height, type.body.height);
      expect(type.synopsis.fontFamily, type.body.fontFamily);
    });

    test('scales with the screen like everything else', () {
      expect(const OckerType(0.5).synopsis.fontSize, const OckerType(1).synopsis.fontSize! / 2);
    });
  });
  group('The title and the room it takes', () {
    test('reserves more than it draws', () {
      // Two separate figures on purpose: the box is what a title costs a
      // block whether it turns out to be type or a wordmark, and the type
      // sits inside it. Collapsing them meant that shrinking the title also
      // shrank the logo.
      const type = OckerType(1);

      expect(type.detailTitle().fontSize, lessThan(type.titleBoxHeight()));
      expect(type.detailTitle().fontSize, closeTo(64 * OckerType.titleTextScale, 0.001));
    });

    test('keeps the box where it was when the type came down', () {
      // The box is measured off the undiminished figure, so the wordmark it
      // holds did not shrink with the fallback text.
      expect(const OckerType(1).titleBoxHeight(), closeTo(64 * 1.08, 0.001));
    });
  });
  test('leaves the two ends of the ladder where they are', () {
    // The upright card sets its prose between these two — the interface size
    // reads small at that width and the full reading size fills the line — so
    // both ends have to stay put for the middle to mean anything.
    const type = OckerType(1);

    expect(type.synopsis.fontSize, closeTo((type.body.fontSize ?? 18) * OckerType.readingScale, 0.001));
    expect(type.body.fontSize, lessThan(type.synopsis.fontSize!));
  });
}
