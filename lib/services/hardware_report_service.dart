import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/app_logger.dart';
import '../utils/device_channel.dart';

/// One line of the hardware report: a name and what the device answered.
class HardwareFact {
  const HardwareFact(this.name, this.value, {this.supported});

  final String name;
  final String value;

  /// True/false where the fact is a capability, null where it is a plain
  /// reading. Drives the tick or cross beside it.
  final bool? supported;
}

class HardwareSection {
  const HardwareSection(this.title, this.facts);

  final String title;
  final List<HardwareFact> facts;
}

/// What the device says it can do — display modes, HDR, audio formats,
/// decoders.
///
/// Read from the platform on every call rather than cached: an AV receiver
/// switched on between two runs, a television woken from standby, or a changed
/// system setting all change the answer, and a stale report is worse than none.
class HardwareReportService {
  const HardwareReportService._();

  static Future<Map<String, dynamic>?> read() async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await deviceChannel.invokeMapMethod<String, dynamic>('getHardwareReport');
      return result;
    } on PlatformException catch (error) {
      appLogger.w('Hardware report unavailable', error: error);
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// The report as flat sections, ready to render and to copy.
  static List<HardwareSection> sectionsFrom(Map<String, dynamic> report, HardwareReportLabels labels) {
    return [
      HardwareSection(labels.device, _device(report['device'], labels)),
      HardwareSection(labels.display, _display(report['display'], labels)),
      HardwareSection(labels.colour, _hdr(report['hdr'], labels)),
      HardwareSection(labels.audio, _audio(report['audio'], labels)),
      HardwareSection(labels.video, _video(report['video'], labels)),
    ].where((section) => section.facts.isNotEmpty).toList();
  }

  static List<HardwareFact> _device(Object? raw, HardwareReportLabels labels) {
    final map = _asMap(raw);
    if (map == null) return const [];
    final model = [map['manufacturer'], map['model']].whereType<String>().join(' ').trim();
    return [
      if (model.isNotEmpty) HardwareFact(labels.model, model),
      if (map['androidRelease'] != null)
        HardwareFact(labels.system, 'Android ${map['androidRelease']} (API ${map['sdkInt']})'),
      if (map['abis'] case final List<Object?> abis when abis.isNotEmpty)
        HardwareFact(labels.architecture, abis.whereType<String>().join(', ')),
      if (map['isTelevision'] case final bool tv)
        HardwareFact(labels.televisionMode, _yesNo(tv, labels), supported: tv),
    ];
  }

  static List<HardwareFact> _display(Object? raw, HardwareReportLabels labels) {
    final map = _asMap(raw);
    if (map == null || map['available'] != true) return [HardwareFact(labels.displayModes, labels.unavailable)];
    final modes = (map['modes'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final canSwitch = map['canSwitch'] == true;
    return [
      if (map['current'] case final String current) HardwareFact(labels.currentMode, current),
      HardwareFact(labels.modeSwitching, canSwitch ? labels.possible : labels.notPossible, supported: canSwitch),
      // Every mode, not a summary: this is the list the automatic-resolution
      // setting picks from, so seeing it answers "why did it not switch".
      for (final mode in modes) HardwareFact(labels.displayMode, mode),
    ];
  }

  static List<HardwareFact> _hdr(Object? raw, HardwareReportLabels labels) {
    final map = _asMap(raw);
    if (map == null) return const [];
    final types = (map['types'] as List?)?.whereType<String>().toList() ?? const <String>[];
    return [
      HardwareFact(labels.hdrFormats, types.isEmpty ? labels.none : types.join(', '), supported: types.isNotEmpty),
      if (map['wideColorGamut'] case final bool wide)
        HardwareFact(labels.wideColour, _yesNo(wide, labels), supported: wide),
      if (map['maxLuminance'] case final num max) HardwareFact(labels.peakBrightness, '${max.round()} nits'),
    ];
  }

  static List<HardwareFact> _audio(Object? raw, HardwareReportLabels labels) {
    final map = _asMap(raw);
    if (map == null) return const [];
    final formats = (map['formats'] as List?) ?? const [];
    return [
      if (map['route'] case final String route) HardwareFact(labels.audioOutput, route),
      if (map['maxChannels'] case final num channels) HardwareFact(labels.channels, '$channels'),
      for (final entry in formats)
        if (_asMap(entry) case final format?)
          HardwareFact(
            '${format['name']}',
            _yesNo(format['supported'] == true, labels),
            supported: format['supported'] == true,
          ),
    ];
  }

  static List<HardwareFact> _video(Object? raw, HardwareReportLabels labels) {
    final list = (raw as List?) ?? const [];
    return [
      for (final entry in list)
        if (_asMap(entry) case final codec?)
          HardwareFact(
            '${codec['name']}',
            codec['hardware'] == true
                ? [
                    labels.hardwareDecoder,
                    if (codec['maxSize'] case final String size) size,
                    if (codec['tunneling'] == true) labels.tunneling,
                  ].join(' · ')
                : labels.noHardwareDecoder,
            supported: codec['hardware'] == true,
          ),
    ];
  }

  static Map<String, dynamic>? _asMap(Object? raw) =>
      raw is Map ? raw.map((key, value) => MapEntry('$key', value)) : null;

  static String _yesNo(bool value, HardwareReportLabels labels) => value ? labels.yes : labels.no;

  /// The whole report as text, for the copy button.
  static String asText(List<HardwareSection> sections) {
    final buffer = StringBuffer();
    for (final section in sections) {
      buffer.writeln('== ${section.title} ==');
      for (final fact in section.facts) {
        buffer.writeln('${fact.name}: ${fact.value}');
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }
}

/// The words the report is rendered in. Passed in rather than read here so
/// the assembly above stays free of the translation layer and can be tested.
class HardwareReportLabels {
  const HardwareReportLabels({
    required this.device,
    required this.display,
    required this.colour,
    required this.audio,
    required this.video,
    required this.model,
    required this.system,
    required this.architecture,
    required this.televisionMode,
    required this.currentMode,
    required this.modeSwitching,
    required this.displayMode,
    required this.displayModes,
    required this.hdrFormats,
    required this.wideColour,
    required this.peakBrightness,
    required this.audioOutput,
    required this.channels,
    required this.hardwareDecoder,
    required this.noHardwareDecoder,
    required this.tunneling,
    required this.possible,
    required this.notPossible,
    required this.unavailable,
    required this.none,
    required this.yes,
    required this.no,
  });

  final String device, display, colour, audio, video;
  final String model, system, architecture, televisionMode;
  final String currentMode, modeSwitching, displayMode, displayModes;
  final String hdrFormats, wideColour, peakBrightness;
  final String audioOutput, channels;
  final String hardwareDecoder, noHardwareDecoder, tunneling;
  final String possible, notPossible, unavailable, none, yes, no;
}
