import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/hardware_report_service.dart';

const _labels = HardwareReportLabels(
  device: 'Gerät',
  display: 'Bildschirm',
  colour: 'Farbe',
  audio: 'Ton',
  video: 'Video',
  model: 'Modell',
  system: 'System',
  architecture: 'Architektur',
  televisionMode: 'Fernsehmodus',
  currentMode: 'Aktuell',
  modeSwitching: 'Moduswechsel',
  displayMode: 'Modus',
  displayModes: 'Bildschirmmodi',
  hdrFormats: 'HDR',
  wideColour: 'Farbraum',
  peakBrightness: 'Helligkeit',
  audioOutput: 'Ausgang',
  channels: 'Kanäle',
  hardwareDecoder: 'Hardware',
  noHardwareDecoder: 'nur Software',
  tunneling: 'Tunneling',
  possible: 'möglich',
  notPossible: 'nicht möglich',
  unavailable: 'nicht verfügbar',
  none: 'keine',
  yes: 'ja',
  no: 'nein',
);

/// What a Shield-class box answers.
Map<String, dynamic> _report({
  List<String> modes = const ['3840x2160 @ 60 Hz', '1920x1080 @ 23.98 Hz'],
  List<String> hdr = const ['HDR10', 'Dolby Vision'],
}) => {
  'device': {'manufacturer': 'NVIDIA', 'model': 'SHIELD', 'androidRelease': '11', 'sdkInt': 30, 'isTelevision': true},
  'display': {'available': true, 'current': modes.first, 'modes': modes, 'canSwitch': modes.length > 1},
  'hdr': {'types': hdr, 'wideColorGamut': true, 'maxLuminance': 540.0},
  'audio': {
    'route': 'HDMI',
    'maxChannels': 8,
    'formats': [
      {'name': 'Dolby Atmos (E-AC-3 JOC)', 'supported': true},
      {'name': 'DTS:X', 'supported': false},
    ],
  },
  'video': [
    {'name': 'HEVC', 'hardware': true, 'maxSize': '4096x2160', 'tunneling': true},
    {'name': 'AV1', 'hardware': false},
  ],
};

List<HardwareFact> _factsOf(List<HardwareSection> sections, String title) =>
    sections.firstWhere((section) => section.title == title).facts;

void main() {
  group('the report as it is read on screen', () {
    test('names every display mode, because that is what the switch picks from', () {
      // A summary would not answer "why did it not switch to 1080p".
      final sections = HardwareReportService.sectionsFrom(_report(), _labels);

      final display = _factsOf(sections, 'Bildschirm');
      expect(display.map((f) => f.value), containsAll(['3840x2160 @ 60 Hz', '1920x1080 @ 23.98 Hz']));
      expect(display.firstWhere((f) => f.name == 'Moduswechsel').supported, isTrue);
    });

    test('a single mode is reported as no switching, not as a failure', () {
      // A phone, or a stick whose maker locked the output. Not a fault.
      final sections = HardwareReportService.sectionsFrom(_report(modes: ['1920x1080 @ 60 Hz']), _labels);

      expect(_factsOf(sections, 'Bildschirm').firstWhere((f) => f.name == 'Moduswechsel').supported, isFalse);
    });

    test('a capability carries a yes or no, a reading carries neither', () {
      final sections = HardwareReportService.sectionsFrom(_report(), _labels);

      final audio = _factsOf(sections, 'Ton');
      expect(audio.firstWhere((f) => f.name.startsWith('Dolby Atmos')).supported, isTrue);
      expect(audio.firstWhere((f) => f.name == 'DTS:X').supported, isFalse);
      expect(audio.firstWhere((f) => f.name == 'Ausgang').supported, isNull, reason: 'a route is not a capability');
    });

    test('a decoder without hardware says so instead of staying silent', () {
      final sections = HardwareReportService.sectionsFrom(_report(), _labels);

      final video = _factsOf(sections, 'Video');
      expect(video.firstWhere((f) => f.name == 'HEVC').value, contains('4096x2160'));
      expect(video.firstWhere((f) => f.name == 'HEVC').value, contains('Tunneling'));
      expect(video.firstWhere((f) => f.name == 'AV1').value, 'nur Software');
    });

    test('no HDR at all is a stated none, not an empty line', () {
      final sections = HardwareReportService.sectionsFrom(_report(hdr: const []), _labels);

      final hdr = _factsOf(sections, 'Farbe').firstWhere((f) => f.name == 'HDR');
      expect(hdr.value, 'keine');
      expect(hdr.supported, isFalse);
    });

    test('a display the system will not describe is named as unavailable', () {
      final report = _report()..['display'] = {'available': false};

      final sections = HardwareReportService.sectionsFrom(report, _labels);

      expect(_factsOf(sections, 'Bildschirm').single.value, 'nicht verfügbar');
    });

    test('a payload from an older build is read as far as it goes', () {
      // Fields arrive from the platform, and a device that answers half of
      // them must not cost the other half. What is missing is named as
      // missing rather than left out, so a gap cannot be mistaken for a
      // capability the device lacks.
      final sections = HardwareReportService.sectionsFrom({
        'device': {'model': 'Box'},
      }, _labels);

      expect(_factsOf(sections, 'Gerät').single.value, 'Box');
      expect(_factsOf(sections, 'Bildschirm').single.value, 'nicht verfügbar');
      expect(sections.map((s) => s.title), isNot(contains('Ton')), reason: 'an absent section stays absent');
    });

    test('the copy is the same report, flat', () {
      final text = HardwareReportService.asText(HardwareReportService.sectionsFrom(_report(), _labels));

      expect(text, contains('== Bildschirm =='));
      expect(text, contains('HDR: HDR10, Dolby Vision'));
    });
  });
}
