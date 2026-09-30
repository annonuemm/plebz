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
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/fork_identity.dart';

import '../test_helpers/prefs.dart';

const _channel = MethodChannel('com.plebz/update_installer');

Map<String, dynamic> _releaseJson({String tag = 'v1.0.1+551', List<Map<String, dynamic>>? assets}) => {
  'tag_name': tag,
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
    test('takes the build number from the tag, the title or a file name', () {
      expect(PlebzUpdateService.buildNumberOf('v1.0.1+551'), 551);
      expect(PlebzUpdateService.buildNumberOf('Plebz 1.0.1 (Build 551)'), 551);
      expect(PlebzUpdateService.buildNumberOf('Plebz-1.0.1-build551-arm64.apk'), 551);
      expect(PlebzUpdateService.buildNumberOf('v1.0.1'), isNull);
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
    }) async {
      final updates = PlebzUpdateService(
        client: MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            return githubStatus == 200
                ? http.Response(jsonEncode(_releaseJson()), 200)
                : http.Response('{"message":"API rate limit exceeded"}', githubStatus);
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
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => checkForPlebzUpdate(
                    context,
                    userInitiated: true,
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

      await tester.tap(find.text(t.plebz.updateNow));
      // The download writes a real file: let real time and frames take turns.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(calls, ['canInstall', 'install']);
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
  });

  group('after an update', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
    });
    tearDown(SettingsService.resetForTesting);

    Future<void> start(WidgetTester tester, {required int build}) async {
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      maybeShowPlebzUpdatedNotice(context, installed: () async => (version: '1.1.0', build: build)),
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
      await SettingsService.instance.write(SettingsService.plebzLastSeenBuild, 557);
      await start(tester, build: 558);

      expect(find.text(t.plebz.updatedTitle), findsOneWidget);
      expect(find.text(body(558)), findsOneWidget);
      expect(SettingsService.instance.read(SettingsService.plebzLastSeenBuild), 558);
    });

    testWidgets('and says it once', (tester) async {
      await SettingsService.instance.write(SettingsService.plebzLastSeenBuild, 558);
      await start(tester, build: 558);

      expect(find.text(t.plebz.updatedTitle), findsNothing);
    });

    testWidgets('a fresh install is not an update', (tester) async {
      await start(tester, build: 558);

      expect(find.text(t.plebz.updatedTitle), findsNothing);
      expect(
        SettingsService.instance.read(SettingsService.plebzLastSeenBuild),
        558,
        reason: 'remembered for next time',
      );
    });

    testWidgets('an app set up before this notice existed was updated', (tester) async {
      await SettingsService.instance.write(SettingsService.onboardingCompleted, true);
      await start(tester, build: 558);

      expect(find.text(t.plebz.updatedTitle), findsOneWidget);
    });
  });
}
