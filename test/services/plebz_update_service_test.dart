import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/plebz_updates.dart';
import 'package:plezy/services/plebz_update_service.dart';
import 'package:plezy/services/plebz_whats_new.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/fork_identity.dart';

import '../test_helpers/prefs.dart';

const _channel = MethodChannel('com.plebz/update_installer');

Map<String, dynamic> _releaseJson({
  String tag = 'v1.0.1+551',
  List<Map<String, dynamic>>? assets,
  bool draft = false,
  bool prerelease = false,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'name': 'Plebz 1.0.1 (Build 551)',
  'body': 'Fixes',
  'assets':
      assets ??
      [
        for (final label in ['arm64-modern-tv-and-phones', 'arm32-older-devices', 'x86_64-emulators-and-chromebooks'])
          {
            'name': 'Plebz-1.0.1-build551-$label.apk',
            'browser_download_url': 'https://example.test/$label.apk',
            'size': 4,
          },
      ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  group('reading a release', () {
    test('an important release is marked in its tag, which still gives the build (Plebz)', () {
      expect(PlebzUpdateService.isImportantTag('v1.22.2+779-wichtig'), isTrue);
      expect(PlebzUpdateService.isImportantTag('v1.22.2+779-important'), isTrue);
      expect(PlebzUpdateService.isImportantTag('v1.22.2+779'), isFalse);
      expect(PlebzUpdateService.isImportantTag('v1.22.2+779-wichtigkeit'), isFalse);
      expect(PlebzUpdateService.buildNumberOf('v1.22.2+779-wichtig'), 779);

      final important = PlebzUpdateService.parseRelease(_releaseJson(tag: 'v1.0.1+551-wichtig'))!;
      expect(important.important, isTrue);
      expect(important.build, 551);
      expect(PlebzUpdateService.parseRelease(_releaseJson())!.important, isFalse);
    });

    test('takes the build number from the tag, the title or a file name', () {
      expect(PlebzUpdateService.buildNumberOf('v1.0.1+551'), 551);
      expect(PlebzUpdateService.buildNumberOf('Plebz 1.0.1 (Build 551)'), 551);
      expect(PlebzUpdateService.buildNumberOf('Plebz-1.0.1-build551-arm64.apk'), 551);
      expect(PlebzUpdateService.buildNumberOf('v1.0.1'), isNull);
    });

    test('a release body reaches the dialog as it stands; none is no notes', () {
      expect(PlebzUpdateService.parseRelease({..._releaseJson(), 'body': '- Fixes'})!.notes, '- Fixes');
      expect(PlebzUpdateService.parseRelease({..._releaseJson(), 'body': ''})!.notes, isEmpty);
      expect(PlebzUpdateService.parseRelease({..._releaseJson()}..remove('body'))!.notes, isEmpty);
    });

    test('newer means a higher build number, whatever the version name says', () {
      final release = PlebzUpdateService.parseRelease(_releaseJson())!;
      expect(release.build, 551);
      expect(PlebzUpdateService.isNewer(release, 550), isTrue);
      expect(PlebzUpdateService.isNewer(release, 551), isFalse);
      expect(PlebzUpdateService.isNewer(release, 600), isFalse);
    });

    test('an installed split APK is compared by its build, not by its version code', () {
      // Flutter's split APKs install as abi × 1000 + build; compared as it
      // stands, 2556 would outrank every release there will ever be.
      expect(PlebzUpdateService.buildFromVersionCode(1556), 556, reason: 'arm32');
      expect(PlebzUpdateService.buildFromVersionCode(2556), 556, reason: 'arm64');
      expect(PlebzUpdateService.buildFromVersionCode(4556), 556, reason: 'x86_64');
      expect(PlebzUpdateService.buildFromVersionCode(556), 556, reason: 'a universal APK');
      final release = PlebzUpdateService.parseRelease({'tag_name': 'v1.1.0+557', 'assets': []})!;
      expect(PlebzUpdateService.isNewer(release, PlebzUpdateService.buildFromVersionCode(2556)), isTrue);
    });

    test("keeps GitHub's sha256 digest for each file", () {
      final release = PlebzUpdateService.parseRelease(
        _releaseJson(
          assets: [
            {
              'name': 'a.apk',
              'browser_download_url': 'https://example.test/a.apk',
              'size': 1,
              'digest': 'sha256:${'A' * 64}',
            },
          ],
        ),
      )!;
      expect(release.assets.single.sha256, 'a' * 64);
    });
  });

  test("picks the APK for the device's own processor order", () {
    final assets = PlebzUpdateService.parseRelease(_releaseJson())!.assets;
    expect(PlebzUpdateService.assetFor(assets, ['arm64-v8a', 'armeabi-v7a'])!.name, contains('arm64'));
    expect(PlebzUpdateService.assetFor(assets, ['armeabi-v7a', 'armeabi'])!.name, contains('arm32'));
    expect(PlebzUpdateService.assetFor(assets, ['x86_64'])!.name, contains('x86_64'));
    expect(PlebzUpdateService.assetFor(assets, ['mips']), isNull);
  });

  group('how often the start-up check offers (Plebz)', () {
    final now = DateTime(2026, 10, 12, 12);
    int daysAgo(int days) => now.subtract(Duration(days: days)).millisecondsSinceEpoch;

    test('as soon as available offers at every start', () {
      expect(
        plebzUpdateOfferDue(
          offer: PlebzUpdateOffer.whenAvailable,
          lastOfferAtMs: daysAgo(0),
          now: now,
          important: false,
        ),
        isTrue,
      );
    });

    test('a spacing waits since the last offer, and never offered is due', () {
      expect(
        plebzUpdateOfferDue(offer: PlebzUpdateOffer.weekly, lastOfferAtMs: daysAgo(6), now: now, important: false),
        isFalse,
      );
      expect(
        plebzUpdateOfferDue(offer: PlebzUpdateOffer.weekly, lastOfferAtMs: daysAgo(7), now: now, important: false),
        isTrue,
      );
      expect(
        plebzUpdateOfferDue(offer: PlebzUpdateOffer.biweekly, lastOfferAtMs: daysAgo(13), now: now, important: false),
        isFalse,
      );
      expect(
        plebzUpdateOfferDue(offer: PlebzUpdateOffer.monthly, lastOfferAtMs: daysAgo(29), now: now, important: false),
        isFalse,
      );
      expect(
        plebzUpdateOfferDue(offer: PlebzUpdateOffer.monthly, lastOfferAtMs: daysAgo(30), now: now, important: false),
        isTrue,
      );
      expect(
        plebzUpdateOfferDue(offer: PlebzUpdateOffer.monthly, lastOfferAtMs: 0, now: now, important: false),
        isTrue,
      );
    });

    test('an important release comes whatever the spacing', () {
      expect(
        plebzUpdateOfferDue(offer: PlebzUpdateOffer.monthly, lastOfferAtMs: daysAgo(1), now: now, important: true),
        isTrue,
      );
    });

    test('a last offer in the future, a clock set back, holds nothing up', () {
      expect(
        plebzUpdateOfferDue(offer: PlebzUpdateOffer.monthly, lastOfferAtMs: daysAgo(-40), now: now, important: false),
        isTrue,
      );
    });

    test('the choice travels with a backup; when it was last offered stays on the device', () {
      expect(PlebzPrefs.resetAndPortable, contains(PlebzPrefs.plebzUpdateOffer));
      expect(PlebzPrefs.resetAndPortable, isNot(contains(PlebzPrefs.plebzLastUpdateOfferAt)));
      expect(PlebzPrefs.portableOnly, isNot(contains(PlebzPrefs.plebzLastUpdateOfferAt)));
    });
  });

  group('downloading', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('plebz_update_test_'));
    tearDown(() => temp.deleteSync(recursive: true));

    PlebzUpdateService service(List<int> body) => PlebzUpdateService(
      client: MockClient((request) async => http.Response.bytes(body, 200)),
      downloadDirectory: () async => temp,
    );

    test('keeps a file that matches its published digest', () async {
      final body = utf8.encode('apk!');
      final asset = PlebzReleaseAsset(
        name: 'Plebz.apk',
        url: Uri.parse('https://example.test/p.apk'),
        size: body.length,
        sha256: sha256.convert(body).toString(),
      );
      final progress = <double>[];

      final file = await service(body).download(asset, onProgress: progress.add);

      expect(file.readAsBytesSync(), body);
      expect(progress.last, 1.0);
    });

    /// Bodies that never finish on their own; closed after each test.
    final openBodies = <StreamController<List<int>>>[];
    tearDown(() async {
      for (final body in openBodies) {
        await body.close();
      }
      openBodies.clear();
    });

    /// A server that sends one chunk and then nothing, as a phone's dropped
    /// connection looks from here.
    PlebzUpdateService stalling({Duration idleTimeout = PlebzUpdateService.downloadIdleTimeout}) => PlebzUpdateService(
      client: MockClient.streaming((request, _) async {
        final body = StreamController<List<int>>();
        openBodies.add(body);
        body.add(utf8.encode('ap'));
        return http.StreamedResponse(body.stream, 200, contentLength: 4);
      }),
      downloadDirectory: () async => temp,
      idleTimeout: idleTimeout,
    );

    final asset = PlebzReleaseAsset(name: 'Plebz.apk', url: Uri.parse('https://example.test/p.apk'), size: 4);

    test('a download that stops arriving fails instead of waiting for ever, and leaves no file (Plebz)', () async {
      await expectLater(
        stalling(idleTimeout: const Duration(milliseconds: 100)).download(asset),
        throwsA(isA<TimeoutException>()),
      );
      expect(File('${temp.path}/updates/Plebz.apk').existsSync(), isFalse);
    });

    test('a download the viewer cancels stops at once, also while no byte comes (Plebz)', () async {
      final cancel = Completer<void>();
      final progress = <double>[];
      final download = stalling().download(
        asset,
        cancelled: cancel.future,
        onProgress: (value) {
          progress.add(value);
          if (!cancel.isCompleted) cancel.complete();
        },
      );

      await expectLater(download.timeout(const Duration(seconds: 5)), throwsA(isA<PlebzUpdateCancelled>()));
      expect(progress, [0.5]);
      expect(File('${temp.path}/updates/Plebz.apk').existsSync(), isFalse);
    });

    test('refuses and deletes a file that does not match', () async {
      final asset = PlebzReleaseAsset(
        name: 'Plebz.apk',
        url: Uri.parse('https://example.test/p.apk'),
        size: 4,
        sha256: 'f' * 64,
      );

      await expectLater(service(utf8.encode('apk!')).download(asset), throwsFormatException);
      expect(File('${temp.path}/updates/Plebz.apk').existsSync(), isFalse);
    });
  });

  group('the check the viewer sees', () {
    final calls = <String>[];
    var canInstall = true;

    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
      debugPlebzUpdatesAvailable = true;
      calls.clear();
      canInstall = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        call,
      ) async {
        calls.add(call.method);
        return switch (call.method) {
          'canInstall' => canInstall,
          _ => true,
        };
      });
    });

    tearDown(() {
      debugPlebzUpdatesAvailable = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
      SettingsService.resetForTesting();
    });

    Future<void> run(
      WidgetTester tester, {
      required int installedBuild,
      required Directory temp,
      int githubStatus = 200,
      bool userInitiated = true,
      Map<String, dynamic>? latest,
      List<Map<String, dynamic>> releases = const [],
    }) async {
      final updates = PlebzUpdateService(
        client: MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            if (githubStatus != 200) return http.Response('{"message":"API rate limit exceeded"}', githubStatus);
            if (!request.url.path.endsWith('/latest')) return http.Response(jsonEncode(releases), 200);
            return http.Response(jsonEncode(latest ?? _releaseJson()), 200);
          }
          return http.Response.bytes(utf8.encode('apk!'), 200);
        }),
        downloadDirectory: () async => temp,
        repository: 'plebz/plebz',
      );
      addTearDown(updates.dispose);
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(MonoPalette.dark),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => checkForPlebzUpdate(
                    context,
                    userInitiated: userInitiated,
                    service: updates,
                    currentBuild: () async => installedBuild,
                    supportedAbis: () async => ['arm64-v8a'],
                  ),
                  child: const Text('check'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('check'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    testWidgets('says so when there is nothing newer', (tester) async {
      final temp = Directory.systemTemp.createTempSync('plebz_update_ui_');
      addTearDown(() => temp.deleteSync(recursive: true));
      await run(tester, installedBuild: 551, temp: temp);

      expect(find.text(t.plebz.upToDate), findsOneWidget);
      expect(find.text(t.plebz.checking), findsNothing, reason: 'the answer replaces "Checking…"');
      expect(calls, isEmpty);
    });

    testWidgets('a GitHub that refuses is a failed check, not "up to date"', (tester) async {
      final temp = Directory.systemTemp.createTempSync('plebz_update_ui_');
      addTearDown(() => temp.deleteSync(recursive: true));
      await run(tester, installedBuild: 550, temp: temp, githubStatus: 403);

      expect(find.text(t.plebz.checkFailed), findsOneWidget);
      expect(find.text(t.plebz.upToDate), findsNothing);
    });

    testWidgets('offers a newer build and hands it to the installer', (tester) async {
      final temp = Directory.systemTemp.createTempSync('plebz_update_ui_');
      addTearDown(() => temp.deleteSync(recursive: true));
      await run(tester, installedBuild: 550, temp: temp);
      expect(find.text(t.plebz.updateAvailableTitle), findsOneWidget);
      expect(find.textContaining('Fixes'), findsOneWidget, reason: "the release's own notes, before saying yes");

      await tester.tap(find.text(t.plebz.updateNow));
      // The download writes a real file: let real time and frames take turns.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(calls, ['canInstall', 'install']);
    });

    testWidgets('says how big the download is before the yes (Plebz)', (tester) async {
      final temp = Directory.systemTemp.createTempSync('plebz_update_ui_');
      addTearDown(() => temp.deleteSync(recursive: true));
      await run(tester, installedBuild: 550, temp: temp);

      expect(find.textContaining(t.plebz.updateSize(size: '4 B')), findsOneWidget);
      expect(find.textContaining(t.plebz.updateOnMobileData), findsNothing, reason: 'no link type is known here');
    });

    testWidgets('without permission to install, it asks for it first', (tester) async {
      final temp = Directory.systemTemp.createTempSync('plebz_update_ui_');
      addTearDown(() => temp.deleteSync(recursive: true));
      canInstall = false;
      await run(tester, installedBuild: 550, temp: temp);
      await tester.tap(find.text(t.plebz.updateNow));
      await tester.pumpAndSettle();

      expect(find.text(t.plebz.installPermissionTitle), findsOneWidget);
      await tester.tap(find.text(t.plebz.openSettings));
      await tester.pumpAndSettle();

      expect(calls, ['canInstall', 'openInstallPermission']);
    });
  });

  group('the start-up offer keeps to "Updates anbieten" (Plebz)', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
      debugPlebzUpdatesAvailable = true;
    });

    tearDown(() {
      debugPlebzUpdatesAvailable = null;
      SettingsService.resetForTesting();
    });

    var listRequests = 0;

    Future<void> startUp(
      WidgetTester tester, {
      required PlebzUpdateOffer offer,
      required Duration lastOfferAgo,
      bool userInitiated = false,
      Map<String, dynamic>? latest,
      List<Map<String, dynamic>> releases = const [],
    }) async {
      final settings = SettingsService.instance;
      await settings.write(PlebzPrefs.plebzUpdateOffer, offer);
      await settings.write(
        PlebzPrefs.plebzLastUpdateOfferAt,
        DateTime.now().subtract(lastOfferAgo).millisecondsSinceEpoch,
      );
      listRequests = 0;
      final updates = PlebzUpdateService(
        client: MockClient((request) async {
          if (!request.url.path.endsWith('/latest')) {
            listRequests++;
            return http.Response(jsonEncode(releases), 200);
          }
          return http.Response(jsonEncode(latest ?? _releaseJson()), 200);
        }),
        repository: 'plebz/plebz',
      );
      addTearDown(updates.dispose);
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(MonoPalette.dark),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => checkForPlebzUpdate(
                    context,
                    userInitiated: userInitiated,
                    service: updates,
                    currentBuild: () async => 550,
                    supportedAbis: () async => ['arm64-v8a'],
                  ),
                  child: const Text('check'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('check'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    int lastOfferAt() => SettingsService.instance.read(PlebzPrefs.plebzLastUpdateOfferAt);

    testWidgets('an ordinary update waits out the spacing', (tester) async {
      await startUp(tester, offer: PlebzUpdateOffer.monthly, lastOfferAgo: const Duration(days: 3));
      final before = lastOfferAt();

      expect(find.text(t.plebz.updateAvailableTitle), findsNothing);
      expect(lastOfferAt(), before, reason: 'nothing shown, nothing offered');
    });

    testWidgets('and is offered once the spacing is over, which starts the next one', (tester) async {
      await startUp(tester, offer: PlebzUpdateOffer.monthly, lastOfferAgo: const Duration(days: 31));

      expect(find.text(t.plebz.updateAvailableTitle), findsOneWidget);
      expect(find.textContaining(t.plebz.updateImportant), findsNothing);
      expect(DateTime.now().millisecondsSinceEpoch - lastOfferAt(), lessThan(60000));
    });

    testWidgets('an important release comes inside the spacing, and says why', (tester) async {
      await startUp(
        tester,
        offer: PlebzUpdateOffer.monthly,
        lastOfferAgo: const Duration(days: 3),
        latest: _releaseJson(tag: 'v1.0.1+551-wichtig'),
      );

      expect(find.text(t.plebz.updateAvailableTitle), findsOneWidget);
      expect(find.textContaining(t.plebz.updateImportant), findsOneWidget);
    });

    testWidgets('so does one an ordinary release has followed since', (tester) async {
      await startUp(
        tester,
        offer: PlebzUpdateOffer.weekly,
        lastOfferAgo: const Duration(days: 1),
        latest: _releaseJson(tag: 'v1.0.2+552'),
        releases: [
          _releaseJson(tag: 'v1.0.2+552'),
          _releaseJson(tag: 'v1.0.1+551-wichtig'),
          _releaseJson(tag: 'v1.0.0+540-wichtig'),
        ],
      );

      expect(find.text(t.plebz.updateAvailableTitle), findsOneWidget);
      expect(find.textContaining(t.plebz.updateImportant), findsOneWidget);
    });

    testWidgets('an important release already installed does not count', (tester) async {
      await startUp(
        tester,
        offer: PlebzUpdateOffer.weekly,
        lastOfferAgo: const Duration(days: 1),
        latest: _releaseJson(tag: 'v1.0.2+552'),
        releases: [
          _releaseJson(tag: 'v1.0.2+552'),
          _releaseJson(tag: 'v1.0.0+540-wichtig'),
        ],
      );

      expect(find.text(t.plebz.updateAvailableTitle), findsNothing);
    });

    testWidgets('a draft or pre-release marked important does not count', (tester) async {
      await startUp(
        tester,
        offer: PlebzUpdateOffer.weekly,
        lastOfferAgo: const Duration(days: 1),
        latest: _releaseJson(tag: 'v1.0.2+552'),
        releases: [
          _releaseJson(tag: 'v1.0.3+553-wichtig', draft: true),
          _releaseJson(tag: 'v1.0.3+554-wichtig', prerelease: true),
          _releaseJson(tag: 'v1.0.2+552'),
        ],
      );

      expect(find.text(t.plebz.updateAvailableTitle), findsNothing);
    });

    testWidgets('as soon as available offers at once and asks GitHub once', (tester) async {
      await startUp(tester, offer: PlebzUpdateOffer.whenAvailable, lastOfferAgo: Duration.zero);

      expect(find.text(t.plebz.updateAvailableTitle), findsOneWidget);
      expect(listRequests, 0);
    });

    testWidgets('asking by hand always shows it', (tester) async {
      await startUp(
        tester,
        offer: PlebzUpdateOffer.monthly,
        lastOfferAgo: const Duration(days: 1),
        userInitiated: true,
      );

      expect(find.text(t.plebz.updateAvailableTitle), findsOneWidget);
    });
  });

  group('the release query', () {
    PlebzUpdateService withStatus(int status) =>
        PlebzUpdateService(client: MockClient((_) async => http.Response('{}', status)), repository: 'plebz/plebz');

    test('a repository without a release is nothing newer', () async {
      expect(await withStatus(404).latestRelease(), isNull);
    });

    test('any other refusal is an error, with its status', () async {
      await expectLater(
        withStatus(403).latestRelease(),
        throwsA(isA<PlebzUpdateCheckException>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('the release list leaves drafts and pre-releases out, and refuses like the latest (Plebz)', () async {
      final updates = PlebzUpdateService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode([
              _releaseJson(tag: 'v1.0.3+553', draft: true),
              _releaseJson(tag: 'v1.0.3+554', prerelease: true),
              _releaseJson(tag: 'v1.0.2+552-wichtig'),
            ]),
            200,
          ),
        ),
        repository: 'plebz/plebz',
      );
      addTearDown(updates.dispose);
      expect((await updates.recentReleases()).map((r) => r.tag), ['v1.0.2+552-wichtig']);
      expect(await withStatus(404).recentReleases(), isEmpty);
      await expectLater(withStatus(403).recentReleases(), throwsA(isA<PlebzUpdateCheckException>()));
    });
  });

  group('after an update', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
    });
    tearDown(SettingsService.resetForTesting);

    Future<void> start(WidgetTester tester, {required int build, List<PlebzWhatsNewEntry> notes = const []}) async {
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(MonoPalette.dark),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => maybeShowPlebzUpdatedNotice(
                    context,
                    installed: () async => (version: '1.1.0', build: build),
                    whatsNew: () async => notes,
                  ),
                  child: const Text('start'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
    }

    String body(int build) => t.plebz.updatedBody(version: '1.1.0', build: build);

    testWidgets('the first start of a newer build says which one is installed', (tester) async {
      await SettingsService.instance.write(PlebzPrefs.plebzLastSeenBuild, 557);
      await start(tester, build: 558);

      expect(find.text(t.plebz.updatedTitle), findsOneWidget);
      expect(find.text(body(558)), findsOneWidget);
      expect(SettingsService.instance.read(PlebzPrefs.plebzLastSeenBuild), 558);
    });

    testWidgets('with what is new since the build last started, a skipped release included', (tester) async {
      await SettingsService.instance.write(PlebzPrefs.plebzLastSeenBuild, 556);
      await start(
        tester,
        build: 558,
        notes: parsePlebzWhatsNew('''
## 1.2.0 (Build 560)
- Not installed yet
## 1.1.1 (Build 558)
- Installed now
## 1.1.0 (Build 557)
- Skipped
## 1.0.0 (Build 556)
- Seen before
'''),
      );

      expect(find.textContaining(body(558)), findsOneWidget);
      expect(find.textContaining('Installed now'), findsOneWidget);
      expect(find.textContaining('Skipped'), findsOneWidget);
      expect(find.textContaining('Seen before'), findsNothing);
      expect(find.textContaining('Not installed yet'), findsNothing);
    });

    testWidgets('and says it once', (tester) async {
      await SettingsService.instance.write(PlebzPrefs.plebzLastSeenBuild, 558);
      await start(tester, build: 558);

      expect(find.text(t.plebz.updatedTitle), findsNothing);
    });

    testWidgets('a fresh install is not an update', (tester) async {
      await start(tester, build: 558);

      expect(find.text(t.plebz.updatedTitle), findsNothing);
      expect(SettingsService.instance.read(PlebzPrefs.plebzLastSeenBuild), 558, reason: 'remembered for next time');
    });

    testWidgets('an app set up before this notice existed was updated', (tester) async {
      await SettingsService.instance.write(PlebzPrefs.onboardingCompleted, true);
      await start(tester, build: 558);

      expect(find.text(t.plebz.updatedTitle), findsOneWidget);
    });
  });
}
