import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tripwires for upstream merges. Plezy's new texts bring its name back, and
/// its new features may reach for its developer's host again; both should fail
/// here rather than turn up in the app.
void main() {
  test('no visible text names Plezy, except where it means the original', () {
    // "Support Plezy" donates to Plezy's developer; the license notice and
    // "Based on Plezy …" name the work this one is modified from.
    const meantAsTheOriginal = {'supportDeveloper', 'appLicenseNotice', 'basedOnUpstream'};
    final offenders = <String>[];
    final files = Directory('lib/i18n').listSync().whereType<File>().where((f) => f.path.endsWith('.i18n.json'));
    for (final file in files) {
      void walk(Object? node, String path) {
        if (node is Map) {
          node.forEach((key, value) => walk(value, path.isEmpty ? '$key' : '$path.$key'));
        } else if (node is String && node.contains('Plezy') && !meantAsTheOriginal.contains(path.split('.').last)) {
          offenders.add('${file.uri.pathSegments.last}: $path');
        }
      }

      walk(jsonDecode(file.readAsStringSync()), '');
    }

    expect(offenders, isEmpty, reason: 'rename these to Plebz, or list them above if they mean the original');
  });

  test('plezy.app appears only where this fork has switched it off', () {
    // Each address sits behind a switch in lib/utils/fork_identity.dart; the
    // certificate list only names the host. A new entry here means an upstream
    // feature talks to Plezy's developer's server — gate it before shipping.
    const known = {
      'lib/services/discord_rpc_service.dart': 1,
      'lib/services/log_upload_service.dart': 1,
      'lib/utils/certificate_trust.dart': 1,
      'lib/utils/fork_identity.dart': 2,
      'lib/watch_together/services/watch_together_relay_endpoint.dart': 1,
    };
    final found = <String, int>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') && !file.path.endsWith('.json')) continue;
      final count = 'plezy.app'.allMatches(file.readAsStringSync()).length;
      if (count > 0) found[file.path] = count;
    }

    expect(found, known);
  });

  test('Sentry resolves to the no-op stand-in, and the SDK does not ship', () {
    // The stand-in answers upstream's calls with nothing; the real package
    // brings a native library, its Java client and its Dart code with it.
    final lock = File('pubspec.lock').readAsStringSync();
    final entry = RegExp(r'\n  sentry_flutter:\n(?:    .*\n)+').firstMatch(lock)?.group(0) ?? '';
    expect(entry, contains('path: "packages/sentry_flutter"'));
    expect(lock, isNot(contains('\n  sentry:\n')), reason: 'the SDK itself is resolved again');
  });
}
