import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/mpv_hwdec.dart';

void main() {
  test('the setting off decodes in software; on, the platform\'s hardware decoder', () {
    expect(mpvHwdecValue(false), 'no');
    final on = mpvHwdecValue(true);
    expect(on, isNot('no'));
    if (Platform.isMacOS) expect(on, 'videotoolbox');
    if (Platform.isLinux || Platform.isWindows) expect(on, 'auto');
  });
}
