import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/iptv/iptv_catchup.dart';

void main() {
  // A fixed evening, so the stamps in the expectations are readable rather
  // than computed the same way the code under test computes them.
  final start = DateTime(2026, 8, 30, 20, 15);
  final now = DateTime(2026, 8, 30, 22, 0);
  final startEpoch = start.millisecondsSinceEpoch ~/ 1000;
  final nowEpoch = now.millisecondsSinceEpoch ~/ 1000;

  String? build({
    required IptvCatchupMode mode,
    String liveUrl = 'http://panel:8080/live/user/pass/12345.ts',
    IptvCatchupInfo? info,
    int durationSeconds = 3600,
  }) => buildIptvCatchupUrl(
    mode: mode,
    liveUrl: liveUrl,
    start: start,
    durationSeconds: durationSeconds,
    now: now,
    info: info,
    xtreamRoot: 'http://panel:8080',
    xtreamUsername: 'user',
    xtreamPassword: 'pass',
  );

  group('Xtream timeshift', () {
    test('addresses the archive by minutes and the panel date shape', () {
      expect(build(mode: IptvCatchupMode.xtream), 'http://panel:8080/timeshift/user/pass/60/2026-08-30:20-15/12345.ts');
    });

    test('keeps the container the channel plays in', () {
      expect(
        build(mode: IptvCatchupMode.xtream, liveUrl: 'http://panel:8080/live/user/pass/12345.m3u8'),
        endsWith('/12345.m3u8'),
      );
    });

    test('takes the stream id from the URL, so a merged copy keeps its own', () {
      // Two playlist entries for one station carry two ids; the archive has to
      // follow whichever copy is playing.
      expect(
        build(mode: IptvCatchupMode.xtream, liveUrl: 'http://panel:8080/live/user/pass/999.ts'),
        contains('/999.ts'),
      );
    });

    test('rounds a part-minute up rather than asking for zero', () {
      expect(build(mode: IptvCatchupMode.xtream, durationSeconds: 90), contains('/2/'));
    });
  });

  group('query form', () {
    test('appends the window when the entry names no template', () {
      expect(
        build(mode: IptvCatchupMode.query),
        'http://panel:8080/live/user/pass/12345.ts?utc=$startEpoch&lutc=$nowEpoch',
      );
    });

    test('respects a URL that already carries a query', () {
      expect(
        build(mode: IptvCatchupMode.query, liveUrl: 'http://host/ch?token=abc'),
        'http://host/ch?token=abc&utc=$startEpoch&lutc=$nowEpoch',
      );
    });

    test('a template that is a whole URL replaces the live one', () {
      expect(
        build(
          mode: IptvCatchupMode.query,
          info: const IptvCatchupInfo(source: 'http://archive/play?begin=\${start}&len=\${duration}'),
        ),
        'http://archive/play?begin=$startEpoch&len=3600',
      );
    });

    test('a bare template is glued onto the live URL', () {
      expect(
        build(
          mode: IptvCatchupMode.query,
          info: const IptvCatchupInfo(source: '?begin={utc}'),
        ),
        'http://panel:8080/live/user/pass/12345.ts?begin=$startEpoch',
      );
    });
  });

  test('append glues the template on as written', () {
    expect(
      build(
        mode: IptvCatchupMode.append,
        info: const IptvCatchupInfo(source: '?utc={utc}&lutc={lutc}'),
      ),
      'http://panel:8080/live/user/pass/12345.ts?utc=$startEpoch&lutc=$nowEpoch',
    );
  });

  test('append without a template refuses rather than guessing', () {
    expect(build(mode: IptvCatchupMode.append), isNull);
  });

  group('Flussonic', () {
    test('puts the window on the last path segment', () {
      expect(
        build(mode: IptvCatchupMode.flussonic, liveUrl: 'http://host/ard/index.m3u8'),
        'http://host/ard/index-$startEpoch-3600.m3u8',
      );
    });

    test('handles a segment without an extension', () {
      expect(
        build(mode: IptvCatchupMode.flussonic, liveUrl: 'http://host/ard/mono'),
        'http://host/ard/mono-$startEpoch-3600',
      );
    });

    test('a URL with no path has nothing to rewrite', () {
      expect(build(mode: IptvCatchupMode.flussonic, liveUrl: 'http://host'), isNull);
    });
  });

  group('placeholders', () {
    test('both spellings are filled, and the date parts too', () {
      expect(
        build(
          mode: IptvCatchupMode.append,
          info: const IptvCatchupInfo(source: '?d={Y}-{m}-{d}T{H}:{M}&o=\${offset}&e=\${end}'),
        ),
        endsWith('?d=2026-08-30T20:15&o=${nowEpoch - startEpoch}&e=${startEpoch + 3600}'),
      );
    });

    test('an unknown placeholder is left standing rather than emptied', () {
      // A provider-specific token this app does not know is still likelier to
      // work as written than replaced with nothing.
      expect(
        build(
          mode: IptvCatchupMode.append,
          info: const IptvCatchupInfo(source: '?x={nonsense}'),
        ),
        endsWith('?x={nonsense}'),
      );
    });
  });

  group('automatic', () {
    test('follows what the entry declares', () {
      expect(
        build(
          mode: IptvCatchupMode.automatic,
          info: const IptvCatchupInfo(declaredMode: 'flussonic'),
          liveUrl: 'http://host/a/index.m3u8',
        ),
        'http://host/a/index-$startEpoch-3600.m3u8',
      );
    });

    test('builds nothing when the entry declares nothing', () {
      expect(build(mode: IptvCatchupMode.automatic), isNull);
    });

    test('off builds nothing even where the entry declares an archive', () {
      expect(
        build(
          mode: IptvCatchupMode.off,
          info: const IptvCatchupInfo(declaredMode: 'shift'),
        ),
        isNull,
      );
    });
  });

  group('window', () {
    test('the entry has the last word', () {
      expect(
        iptvCatchupWindowDays(
          mode: IptvCatchupMode.automatic,
          info: const IptvCatchupInfo(declaredMode: 'shift', days: 3),
          providerDays: 7,
          sourceDays: 5,
        ),
        3,
      );
    });

    test('a panel that reports a window is believed over the source setting', () {
      expect(iptvCatchupWindowDays(mode: IptvCatchupMode.automatic, providerDays: 7, sourceDays: 2), 7);
    });

    test('a provider that declares nothing gets no archive on automatic', () {
      expect(iptvCatchupWindowDays(mode: IptvCatchupMode.automatic, sourceDays: 5), isNull);
    });

    test('an explicit mode is itself the assertion that there is one', () {
      expect(iptvCatchupWindowDays(mode: IptvCatchupMode.xtream, sourceDays: 5), 5);
      expect(iptvCatchupWindowDays(mode: IptvCatchupMode.xtream), kDefaultIptvCatchupDays);
    });

    test('off is off, whatever anyone declares', () {
      expect(iptvCatchupWindowDays(mode: IptvCatchupMode.off, providerDays: 7, sourceDays: 5), isNull);
    });
  });
}
