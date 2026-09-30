import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/resolution_label.dart';

void main() {
  group('resolutionLabelFromDimensions', () {
    test('labels nominal frames by their tier', () {
      expect(resolutionLabelFromDimensions(3840, 2160), '4k');
      expect(resolutionLabelFromDimensions(1920, 1080), '1080');
      expect(resolutionLabelFromDimensions(1280, 720), '720');
      expect(resolutionLabelFromDimensions(854, 480), '480');
    });

    test('a scope master keeps its tier despite the short height', () {
      expect(resolutionLabelFromDimensions(3840, 1600), '4k');
      expect(resolutionLabelFromDimensions(1920, 800), '1080');
    });

    test('a mastering crop a few pixels short still counts as its tier', () {
      // The report that started this: Jellyfin calls this file 4K, the app
      // called it 1080p because 3828 missed an exact >= 3840 test.
      expect(resolutionLabelFromDimensions(3828, 1596), '4k');
      expect(resolutionLabelFromDimensions(3712, 1552), '4k');
      expect(resolutionLabelFromDimensions(1912, 796), '1080');
      expect(resolutionLabelFromDimensions(1276, 536), '720');
    });

    test('the tolerance does not reach down into the tier below', () {
      // 1440p and 2K stay 1080p; nothing short of a real 4K frame is promoted.
      expect(resolutionLabelFromDimensions(2560, 1440), '1080');
      expect(resolutionLabelFromDimensions(2048, 858), '1080');
      expect(resolutionLabelFromDimensions(3200, 1340), '1080');
      // A 720p frame must not become 1080p.
      expect(resolutionLabelFromDimensions(1280, 720), '720');
    });

    test('anamorphic frames are read from the taller dimension', () {
      // 1440x1080 (HDV) displays as 1080p even though the stored width is
      // below the 1080p width cutoff.
      expect(resolutionLabelFromDimensions(1440, 1080), '1080');
    });

    test('sub-480 frames report their raw height', () {
      expect(resolutionLabelFromDimensions(640, 360), '360');
      expect(resolutionLabelFromDimensions(426, 240), '240');
    });

    test('missing dimensions produce no label', () {
      expect(resolutionLabelFromDimensions(null, null), isNull);
    });

    test('a known width alone is enough', () {
      expect(resolutionLabelFromDimensions(3840, null), '4k');
      expect(resolutionLabelFromDimensions(1920, null), '1080');
    });
  });

  group('resolutionLabelFromHeight', () {
    test('maps nominal heights onto tiers', () {
      expect(resolutionLabelFromHeight(2160), '4k');
      expect(resolutionLabelFromHeight(1080), '1080');
      expect(resolutionLabelFromHeight(720), '720');
      expect(resolutionLabelFromHeight(480), '480');
    });

    test('returns null without a height', () {
      expect(resolutionLabelFromHeight(null), isNull);
    });

    test('falls back to the raw height below the lowest tier', () {
      expect(resolutionLabelFromHeight(360), '360');
    });

    test('cannot recover a scope tier from height alone', () {
      // Documented limitation: 1596 could be a cropped 4K frame or a tall
      // 1080p one. Callers that know the width must pass it.
      expect(resolutionLabelFromHeight(1596), '1080');
    });
  });
}
