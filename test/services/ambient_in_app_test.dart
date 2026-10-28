import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/services/ambient/ambient_feed.dart';
import 'package:plezy/services/ambient/ambient_in_app.dart';
import 'package:plezy/services/home_rows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/ambient_in_app');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const delay = Duration(minutes: 2);

  late List<MethodCall> calls;
  late bool held;
  late bool typing;
  late AmbientFeed feed;
  late AmbientInApp saver;

  /// What the app asked of the Android side, the scene writes left out.
  List<String> asked() => [
    for (final call in calls)
      if (call.method != 'publish') call.method,
  ];

  int shows() => asked().where((method) => method == 'showInApp').length;

  setUpAll(() => initializeDateFormatting());

  setUp(() {
    calls = [];
    held = false;
    typing = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    feed = AmbientFeed(
      channel: channel,
      rows: HomeRows(channel: const MethodChannel('test/ambient_in_app_rows'), supported: true),
      reminderChanges: ChangeNotifier(),
      reminderSource: () => [],
      supported: true,
      debounce: Duration.zero,
    );
    saver = AmbientInApp(feed: feed, screenHeld: () async => held, typing: () => typing, supported: true);
  });

  tearDown(() {
    saver.debugReset();
    feed.debugReset();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('after the time without input it lays itself over the app, and holds the device\'s own off meanwhile', () {
    fakeAsync((async) {
      saver.configure(enabled: true, delay: delay);
      async.flushMicrotasks();
      expect(asked(), ['setKeepAwake']);
      expect(calls.single.arguments, {'on': true});

      async.elapse(delay - const Duration(seconds: 1));
      expect(shows(), 0);
      async.elapse(const Duration(seconds: 2));
      expect(shows(), 1);
      expect(saver.showing, isTrue);
      expect(calls.map((call) => call.method), contains('publish'), reason: 'the scenes are written first');
    });
  });

  test('input starts the clock over', () {
    fakeAsync((async) {
      saver.configure(enabled: true, delay: delay);
      async.elapse(const Duration(seconds: 90));
      saver.noteActivity();
      async.elapse(const Duration(seconds: 60));
      expect(shows(), 0);
      async.elapse(const Duration(seconds: 61));
      expect(shows(), 1);
    });
  });

  test('a playing video or a text being typed keeps it away', () {
    fakeAsync((async) {
      held = true;
      saver.configure(enabled: true, delay: delay);
      async.elapse(delay * 3);
      expect(shows(), 0);

      held = false;
      typing = true;
      async.elapse(delay * 3);
      expect(shows(), 0);

      typing = false;
      async.elapse(delay + const Duration(seconds: 1));
      expect(shows(), 1);
    });
  });

  test('input the app sees while it shows takes it away, and the clock starts over', () {
    fakeAsync((async) {
      saver.configure(enabled: true, delay: delay);
      async.elapse(delay + const Duration(seconds: 1));
      expect(saver.showing, isTrue);

      saver.noteActivity();
      async.flushMicrotasks();
      expect(asked().last, 'hideInApp');
      expect(saver.showing, isFalse);

      async.elapse(delay + const Duration(seconds: 1));
      expect(shows(), 2);
    });
  });

  test('a key that ended it on the Android side starts the clock over', () {
    fakeAsync((async) {
      saver.configure(enabled: true, delay: delay);
      async.elapse(delay + const Duration(seconds: 1));
      expect(saver.showing, isTrue);

      messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('inAppClosed')),
        (_) {},
      );
      async.flushMicrotasks();
      expect(saver.showing, isFalse);
      expect(asked(), isNot(contains('hideInApp')), reason: 'it is gone already');

      async.elapse(delay + const Duration(seconds: 1));
      expect(shows(), 2);
    });
  });

  test('switched off it goes, and the device\'s own screensaver may start again', () {
    fakeAsync((async) {
      saver.configure(enabled: true, delay: delay);
      async.elapse(delay + const Duration(seconds: 1));
      calls.clear();

      saver.configure(enabled: false, delay: delay);
      async.flushMicrotasks();
      expect(asked(), ['hideInApp', 'setKeepAwake']);
      expect(calls.last.arguments, {'on': false});

      async.elapse(delay * 3);
      expect(shows(), 0);
    });
  });

  test('in the background it neither waits nor keeps the device awake', () {
    fakeAsync((async) {
      saver.configure(enabled: true, delay: delay);
      async.flushMicrotasks();
      calls.clear();

      saver.didChangeAppLifecycleState(AppLifecycleState.paused);
      async.flushMicrotasks();
      expect(calls.single.arguments, {'on': false});
      async.elapse(delay * 3);
      expect(shows(), 0);

      saver.didChangeAppLifecycleState(AppLifecycleState.resumed);
      async.elapse(delay + const Duration(seconds: 1));
      expect(asked(), ['setKeepAwake', 'setKeepAwake', 'showInApp']);
      expect(calls.lastWhere((call) => call.method == 'setKeepAwake').arguments, {'on': true});
    });
  });
}
