import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  test('the PIN is asked of Simkl alone, without a relay page on Plezy\'s host', () async {
    final asked = <Uri>[];
    final auth = SimklAuthService(
      httpClient: MockClient((request) async {
        asked.add(request.url);
        return http.Response(jsonEncode({'device_code': 'd', 'user_code': 'ABCD', 'expires_in': 900}), 200);
      }),
    );
    addTearDown(auth.dispose);

    final code = await auth.createDeviceCode();

    expect(code.userCode, 'ABCD');
    expect(asked.single.host, 'api.simkl.com');
    expect(asked.single.queryParameters.containsKey('redirect'), isFalse);
    expect(asked.single.toString(), isNot(contains('plezy.app')));
  });
}
