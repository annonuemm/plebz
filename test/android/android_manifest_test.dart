import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  test('Android backs up nothing of the app: tokens and the key that seals them stay on the device', () {
    final manifest = XmlDocument.parse(File('android/app/src/main/AndroidManifest.xml').readAsStringSync());
    final application = manifest.findAllElements('application').single;
    expect(application.getAttribute('android:allowBackup'), 'false');
  });
}
