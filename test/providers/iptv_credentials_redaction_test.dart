import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/iptv/iptv_source.dart';
import 'package:plezy/providers/iptv_sources_provider.dart';
import 'package:plezy/utils/log_redaction_manager.dart';

import '../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    LogRedactionManager.clearTrackedValues();
  });

  test('an Xtream account never reaches the log through a stream address', () async {
    // The panel carries the account in the path — `/live/<user>/<pass>/…` —
    // so every address the player logs would hand out the subscription to
    // whoever the log is pasted to. And a log is the first thing anybody
    // sends when something misbehaves.
    final provider = IptvSourcesProvider(profileId: 'p', buildSource: (_) => throw UnimplementedError());
    addTearDown(provider.dispose);
    await provider.save(
      const IptvSource(
        id: 'src',
        name: 'Panel',
        kind: IptvSourceKind.xtream,
        baseUrl: 'http://panel:8080',
        username: 'aB3cD4eF5g',
        password: 'hJ6kL7mN8p',
      ),
    );

    const address = 'http://panel:8080/timeshift/aB3cD4eF5g/hJ6kL7mN8p/80/2026-09-06:15-30/393715.m3u8';
    final redacted = LogRedactionManager.redact(address);

    expect(redacted, isNot(contains('aB3cD4eF5g')));
    expect(redacted, isNot(contains('hJ6kL7mN8p')));
    // The rest survives, or the log stops being useful for diagnosing.
    expect(redacted, contains('/timeshift/'));
    expect(redacted, contains('393715.m3u8'));
  });

  test('sources restored on the next start are registered too', () async {
    final first = IptvSourcesProvider(profileId: 'p', buildSource: (_) => throw UnimplementedError());
    await first.save(
      const IptvSource(
        id: 'src',
        name: 'Panel',
        kind: IptvSourceKind.xtream,
        baseUrl: 'http://panel:8080',
        username: 'stored-user',
        password: 'stored-pass',
      ),
    );
    first.dispose();
    LogRedactionManager.clearTrackedValues();

    final second = IptvSourcesProvider(profileId: 'p', buildSource: (_) => throw UnimplementedError());
    addTearDown(second.dispose);
    await second.ensureLoaded();

    expect(LogRedactionManager.redact('user=stored-user pass=stored-pass'), isNot(contains('stored-user')));
  });
}
