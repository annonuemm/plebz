import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/models/trackers/device_code.dart';
import 'package:plezy/services/trackers/simkl/simkl_auth_service.dart';
import 'package:plezy/services/trackers/tracker_constants.dart';
import 'package:plezy/utils/fork_identity.dart';

/// Simkl is back in this fork (2026-10-06), signing in straight at Simkl.
void main() {
  test('Simkl is offered again; the other trackers stay out', () {
    expect(isTrackerAvailable(TrackerService.simkl), isTrue);
    for (final service in [TrackerService.trakt, TrackerService.mal, TrackerService.anilist, TrackerService.mdblist]) {
      expect(isTrackerAvailable(service), isFalse, reason: service.name);
    }
  });

  test('the device code is asked of Simkl alone, without a relay page on Plezy\'s host', () async {
    final asked = <http.Request>[];
    final auth = SimklAuthService(
      httpClient: MockClient((request) async {
        asked.add(request);
        return http.Response(
          jsonEncode({
            'device_code': 'd',
            'user_code': 'ABCD',
            'verification_uri': 'https://simkl.com/pin',
            'expires_in': 900,
          }),
          200,
        );
      }),
    );
    addTearDown(auth.dispose);

    final code = await auth.createDeviceCode();

    expect(code.userCode, 'ABCD');
    expect(asked.single.url.host, 'api.simkl.com');
    expect(asked.single.url.path, '/oauth2/device');
    expect(asked.single.url.queryParameters.containsKey('redirect'), isFalse);
    expect(asked.single.body, isNot(contains('redirect')));
    expect('${asked.single.url} ${asked.single.body}', isNot(contains('plezy.app')));
  });

  test('the token poll goes to Simkl alone', () async {
    final asked = <Uri>[];
    final auth = SimklAuthService(
      httpClient: MockClient((request) async {
        asked.add(request.url);
        return http.Response(jsonEncode({'error': 'authorization_pending'}), 400);
      }),
    );
    addTearDown(auth.dispose);

    await auth.probe(
      const DeviceCode(
        deviceCode: 'd',
        userCode: 'ABCD',
        verificationUrl: 'https://simkl.com/pin',
        expiresIn: 900,
        interval: 5,
      ),
    );

    expect(asked.single.host, 'api.simkl.com');
    expect(asked.single.toString(), isNot(contains('plezy.app')));
  });
}
