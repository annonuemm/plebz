import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_version.dart';

void main() {
  MediaVersion version(String resolution, String codec, String container, {String id = ''}) {
    return MediaVersion(id: id, videoResolution: resolution, videoCodec: codec, container: container);
  }

  group('labels', () {
    test('the technical label describes the file, without the version name', () {
      const withName = MediaVersion(
        id: 'a',
        name: '1080p',
        videoResolution: '1080',
        videoCodec: 'h264',
        container: 'mkv',
        bitrate: 8900,
      );

      expect(withName.technicalLabel, '1080p H.264 MKV (8.9 Mbps)');
      // Backends routinely name a source after its resolution; a comparison
      // row that used displayLabel would then read "1080p · 1080p H.264 MKV".
      expect(withName.displayLabel, startsWith('1080p · '));
    });

    test('a named cut still prefixes the technical label', () {
      const cut = MediaVersion(id: 'a', name: "Director's Cut", videoResolution: '1080', videoCodec: 'h264');

      expect(cut.displayLabel, "Director's Cut · 1080p H.264");
      expect(cut.technicalLabel, '1080p H.264');
    });

    test('a name with nothing technical behind it stands alone', () {
      const bare = MediaVersion(id: 'a', name: 'Remux');

      expect(bare.displayLabel, 'Remux');
    });

    test('an unnamed version reads the same either way', () {
      const plain = MediaVersion(id: 'a', videoResolution: '4k', videoCodec: 'hevc', container: 'mkv');

      expect(plain.displayLabel, plain.technicalLabel);
      expect(plain.technicalLabel, '4K HEVC MKV');
    });
  });

  group('MediaVersion.findMatchingIndex', () {
    test('exact match globally outranks an earlier resolution+codec match', () {
      final versions = [version('1080', 'h264', 'mp4'), version('4k', 'hevc', 'mkv')];

      expect(MediaVersion.findMatchingIndex(versions, {'1080:h264:mkv', '4k:hevc:mkv'}), 1);
    });

    test('exact match globally outranks an earlier resolution-only match', () {
      final versions = [version('1080', 'vp9', 'mp4'), version('4k', 'hevc', 'mkv')];

      expect(MediaVersion.findMatchingIndex(versions, {'1080:h264:avi', '4k:hevc:mkv'}), 1);
    });

    test('resolution+codec globally outranks an earlier resolution-only match', () {
      final versions = [version('1080', 'vp9', 'mp4'), version('4k', 'hevc', 'mp4')];

      expect(MediaVersion.findMatchingIndex(versions, {'1080:h264:avi', '4k:hevc:mkv'}), 1);
    });

    test('skips malformed signatures without blocking a later valid exact match', () {
      final versions = [version('1080', 'h264', 'mkv')];

      expect(MediaVersion.findMatchingIndex(versions, {'malformed', '1080:h264:mkv'}), 0);
      expect(MediaVersion.findMatchingIndex(versions, {'malformed', 'also:malformed'}), isNull);
    });

    test('earlier accepted signature wins a same-tier tie even with a later candidate', () {
      final versions = [version('4k', 'hevc', 'mp4'), version('1080', 'h264', 'mp4')];

      expect(MediaVersion.findMatchingIndex(versions, {'1080:h264:mkv', '4k:hevc:mkv'}), 1);
    });

    test('retains valid three-field signatures with empty fields', () {
      const versions = [MediaVersion(id: 'empty')];

      expect(MediaVersion.findMatchingIndex(versions, {'::'}), 0);
    });

    test('earlier candidate wins when one signature has multiple same-tier matches', () {
      final versions = [version('1080', 'h264', 'mp4'), version('1080', 'h264', 'avi')];

      expect(MediaVersion.findMatchingIndex(versions, {'1080:h264:mkv'}), 0);
    });

    test('singleton signatures retain exact then codec then resolution priority', () {
      final resolutionOnly = version('1080', 'vp9', 'mp4');
      final resolutionAndCodec = version('1080', 'h264', 'mp4');
      final exact = version('1080', 'h264', 'mkv');
      const accepted = {'1080:h264:mkv'};

      expect(MediaVersion.findMatchingIndex([resolutionOnly, resolutionAndCodec, exact], accepted), 2);
      expect(MediaVersion.findMatchingIndex([resolutionOnly, resolutionAndCodec], accepted), 1);
      expect(MediaVersion.findMatchingIndex([resolutionOnly], accepted), 0);
    });

    test('returns null for empty candidates or accepted signatures', () {
      final candidate = version('1080', 'h264', 'mkv');

      expect(MediaVersion.findMatchingIndex(const [], {'1080:h264:mkv'}), isNull);
      expect(MediaVersion.findMatchingIndex([candidate], const {}), isNull);
    });
  });
}
