import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/library_copy_quality.dart';
import 'package:plezy/media/media_part.dart';
import 'package:plezy/media/media_stream.dart';
import 'package:plezy/media/media_version.dart';

import '../test_helpers/media_items.dart';

MediaStream _audio(String codec, {String? profile, String? title, bool isDefault = false, int? channels}) =>
    MediaStream(
      id: 'a-$codec-${title ?? ''}',
      kind: MediaStreamKind.audio,
      codec: codec,
      profile: profile,
      title: title,
      isDefault: isDefault,
      channels: channels,
    );

MediaVersion _version({
  int? width,
  int? height,
  String? resolution,
  int bitrate = 0,
  bool hdr = false,
  bool hdr10Plus = false,
  bool dolbyVision = false,
  int? dolbyVisionProfile,
  List<MediaStream> audio = const [],
}) => MediaVersion(
  id: 'v',
  width: width,
  height: height,
  videoResolution: resolution,
  bitrate: bitrate,
  parts: [
    MediaPart(
      id: 'p',
      streams: [
        MediaStream(
          id: 'video',
          kind: MediaStreamKind.video,
          hdr: hdr,
          hdr10Plus: hdr10Plus,
          dolbyVision: dolbyVision,
          dolbyVisionProfile: dolbyVisionProfile,
        ),
        ...audio,
      ],
    ),
  ],
);

LibraryCopyQuality _of(MediaVersion version, {int? episodes, bool dolbyVisionDisabled = false}) =>
    LibraryCopyQuality.of(
      testMediaItem(mediaVersions: [version]),
      episodes: episodes,
      dolbyVisionDisabled: dolbyVisionDisabled,
    );

/// Whether [a] ranks before [b].
bool _before(LibraryCopyQuality a, LibraryCopyQuality b) => compareLibraryCopyQuality(a, b) < 0;

void main() {
  group('resolution', () {
    test('a 4K film in scope is 4K, though its height is not', () {
      expect(_of(_version(width: 3840, height: 1600)).resolution, 2160);
      expect(_of(_version(width: 1920, height: 800)).resolution, 1080);
      expect(_of(_version(resolution: '4k')).resolution, 2160);
    });
  });

  group('order', () {
    test('picture first: 4K plain beats 1080p with Dolby Vision and Atmos', () {
      final plain4k = _of(_version(resolution: '4k', audio: [_audio('aac')]));
      final rich1080 = _of(
        _version(
          resolution: '1080',
          dolbyVision: true,
          audio: [_audio('truehd', title: 'TrueHD Atmos 7.1')],
        ),
      );
      expect(_before(plain4k, rich1080), isTrue);
    });

    test('at the same resolution: Dolby Vision, then HDR10+, then HDR, then SDR', () {
      final dv = _of(_version(resolution: '4k', dolbyVision: true, dolbyVisionProfile: 8));
      final hdr10Plus = _of(_version(resolution: '4k', hdr: true, hdr10Plus: true));
      final hdr = _of(_version(resolution: '4k', hdr: true));
      final sdr = _of(_version(resolution: '4k'));
      expect([sdr, hdr, dv, hdr10Plus]..sort(compareLibraryCopyQuality), [dv, hdr10Plus, hdr, sdr]);
    });

    test('then the sound, by class: Atmos, lossless or DTS-HD, lossy surround, stereo', () {
      LibraryCopyQuality withAudio(MediaStream stream) => _of(_version(resolution: '4k', audio: [stream]));
      final atmos = withAudio(_audio('eac3', title: 'Dolby Digital Plus Atmos'));
      final trueHd = withAudio(_audio('truehd'));
      final dtsHdMa = withAudio(_audio('dts', profile: 'DTS-HD MA'));
      final eac3 = withAudio(_audio('eac3', channels: 6));
      final ac3 = withAudio(_audio('ac3', channels: 6));
      final dtsCore = withAudio(_audio('dts', channels: 6));
      final stereo = withAudio(_audio('aac', channels: 2));
      expect(atmos.audio, greaterThan(trueHd.audio));
      expect(trueHd.audio, dtsHdMa.audio);
      expect(dtsHdMa.audio, greaterThan(eac3.audio));
      expect(eac3.audio, ac3.audio, reason: 'E-AC-3 5.1 and AC3 5.1 are one class');
      expect(ac3.audio, dtsCore.audio);
      expect(ac3.audio, greaterThan(stereo.audio));
    });

    test('E-AC-3 does not outrank AC3 at a quarter of the bitrate', () {
      // The case seen on the television: the same series in 4K Dolby Vision
      // on both servers, E-AC-3 at about 7 Mbit/s with 38 of 39 episodes on
      // one, AC3 at about 26 Mbit/s with all 39 on the other.
      final jellyfin = _of(
        _version(
          resolution: '4k',
          bitrate: 7000,
          dolbyVision: true,
          dolbyVisionProfile: 8,
          audio: [_audio('eac3', channels: 6)],
        ),
        episodes: 38,
      );
      final plex = _of(
        _version(
          resolution: '4k',
          bitrate: 26000,
          dolbyVision: true,
          dolbyVisionProfile: 8,
          audio: [_audio('ac3', channels: 6)],
        ),
        episodes: 39,
      );
      expect(_before(plex, jellyfin), isTrue);
    });

    test('the track that plays is the one that counts', () {
      // A German AC3 marked default beside an English Atmos track: the
      // German one plays, so this copy sounds like AC3.
      final quality = _of(
        _version(
          resolution: '4k',
          audio: [
            _audio('truehd', title: 'English TrueHD Atmos'),
            _audio('ac3', title: 'Deutsch', isDefault: true),
          ],
        ),
      );
      expect(quality.audio, _of(_version(resolution: '4k', audio: [_audio('ac3')])).audio);
    });

    test('then the bitrate', () {
      final thick = _of(_version(resolution: '4k', bitrate: 60000));
      final thin = _of(_version(resolution: '4k', bitrate: 15000));
      expect(_before(thick, thin), isTrue);
    });

    test('for a series, quality before completeness; episodes only break a tie', () {
      final uhdSeasonOne = _of(_version(resolution: '4k'), episodes: 8);
      final hdComplete = _of(_version(resolution: '1080'), episodes: 19);
      expect(_before(uhdSeasonOne, hdComplete), isTrue);

      final hdPartial = _of(_version(resolution: '1080'), episodes: 8);
      expect(_before(hdComplete, hdPartial), isTrue);
    });

    test('what nobody could measure comes last', () {
      final known = _of(_version(resolution: '720'));
      expect(compareLibraryCopyQuality(known, null), lessThan(0));
      expect(compareLibraryCopyQuality(null, known), greaterThan(0));
      expect(compareLibraryCopyQuality(_of(_version()), known), greaterThan(0));
      expect(compareLibraryCopyQuality(null, null), 0);
    });
  });

  group('Dolby Vision switched off', () {
    test('profile 8 is worth its HDR10 base layer', () {
      final p8 = _of(_version(resolution: '4k', dolbyVision: true, dolbyVisionProfile: 8), dolbyVisionDisabled: true);
      expect(p8.dynamicRange, _of(_version(resolution: '4k', hdr: true)).dynamicRange);
    });

    test('profile 5 has no base layer and stays Dolby Vision', () {
      final p5 = _of(_version(resolution: '4k', dolbyVision: true, dolbyVisionProfile: 5), dolbyVisionDisabled: true);
      expect(p5.dynamicRange, 3);
    });
  });

  test('a film with several versions is worth its best one', () {
    final item = testMediaItem(
      mediaVersions: [
        _version(resolution: '1080'),
        _version(resolution: '4k', dolbyVision: true),
      ],
    );
    final quality = LibraryCopyQuality.of(item);
    expect(quality.resolution, 2160);
    expect(quality.dynamicRange, 3);
  });

  test('labels name the picture and the sound, not the bitrate', () {
    final quality = _of(
      _version(
        resolution: '4k',
        bitrate: 50000,
        dolbyVision: true,
        dolbyVisionProfile: 8,
        audio: [_audio('truehd', title: 'TrueHD Atmos')],
      ),
    );
    expect(quality.labels.first, '4K');
    expect(quality.labels, contains('DV P8'));
    expect(quality.labels.last, contains('Atmos'));
    expect(quality.labels.any((label) => label.contains('bit/s')), isFalse);
  });
}
