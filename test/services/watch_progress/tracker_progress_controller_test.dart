import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/trackers/simkl/simkl_client.dart';
import 'package:plezy/services/trackers/tracker_session.dart';
import 'package:plezy/services/watch_progress/external_id_index_client.dart';
import 'package:plezy/services/watch_progress/progress_routing.dart';
import 'package:plezy/services/watch_progress/tracker_progress_controller.dart';
import 'package:plezy/utils/external_ids.dart';
import 'package:plezy/utils/watch_state_notifier.dart';

import '../../test_helpers/media_items.dart';

class _Server implements ExternalIdIndexClient {
  _Server(this.index);

  Map<String, ExternalIds> index;
  int asked = 0;
  bool down = false;

  /// What each read asked for additions since; null for a whole read.
  final sinces = <int?>[];

  /// When the newest title was added; while null, the server names no time
  /// and is always read whole.
  int? newest;

  /// What a read of additions answers.
  Map<String, ExternalIds> added = const {};

  @override
  Future<ExternalIdIndexRead> fetchExternalIdIndex({int? addedSince}) async {
    asked++;
    sinces.add(addedSince);
    if (down) throw const SocketException('receive timed out');
    if (addedSince != null) return ExternalIdIndexRead(Map.of(added), complete: false, newest: newest);
    return ExternalIdIndexRead(Map.of(index), complete: true, newest: newest);
  }
}

/// A Simkl account where film tmdb 101 is watched — or, once [down], an
/// account that cannot be reached.
class _Simkl {
  bool down = false;
  final asked = <Uri>[];

  SimklClient client() => SimklClient(
    const TrackerSession(accessToken: 't', refreshToken: '', expiresAt: 0, createdAt: 0),
    onSessionInvalidated: () {},
    httpClient: MockClient((request) async {
      asked.add(request.url);
      if (down) return http.Response('', 503);
      final body = switch (request.url.path) {
        '/sync/activities' => {'all': 'a1'},
        '/sync/playback' => const [],
        _ => {
          'movies': [
            {
              'movie': {
                'ids': {'simkl': 1, 'tmdb': 101},
              },
              'status': 'completed',
            },
          ],
        },
      };
      return http.Response(jsonEncode(body), 200, headers: const {'content-type': 'application/json'});
    }),
  );
}

void main() {
  final controller = TrackerProgressController.instance;
  late Directory root;
  late _Simkl simkl;
  late _Server server;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tracker_watch_test');
    controller.rootDirectory = () async => root;
    simkl = _Simkl();
    server = _Server({'film': const ExternalIds(tmdb: 101)});
  });

  tearDown(() async {
    await controller.debugFlush();
    controller.debugReset();
    ProgressRouting.instance.debugReset();
    await root.delete(recursive: true);
  });

  final film = testMediaItem(id: 'film', serverId: 'plex', viewCount: 0);
  final other = testMediaItem(id: 'other', serverId: 'plex', viewCount: 2);

  Future<void> bind({bool trackerLed = true, String profile = 'anna'}) {
    final client = simkl.client();
    addTearDown(client.dispose);
    return controller.bind(profileId: profile, trackerLed: trackerLed, simkl: client, servers: {'plex': server});
  }

  test('a tracker-led profile sees Simkl\'s state on the server\'s items', () async {
    final revision = controller.revision.value;
    await bind();

    expect(controller.isActive, isTrue);
    expect(ProgressRouting.instance.serverKeepsWatchState, isFalse);
    expect(ProgressRouting.overlay(film).isWatched, isTrue);
    expect(
      ProgressRouting.overlay(other).isWatched,
      isFalse,
      reason: 'the shared account\'s mark is not this profile\'s',
    );
    expect(controller.revision.value, greaterThan(revision));
    expect(server.asked, 1);
  });

  test('what was learnt is kept on disk, for a start without Simkl', () async {
    await bind();
    await controller.debugFlush();
    controller.debugReset();
    controller.rootDirectory = () async => root;
    simkl.down = true;

    await bind();

    expect(ProgressRouting.overlay(film).isWatched, isTrue);
  });

  test('a mark made here shows at once, before Simkl echoes it', () async {
    await bind();

    WatchStateNotifier().notifyWatched(item: other, isNowWatched: true);
    expect(ProgressRouting.overlay(other).isWatched, isTrue);

    final episode = testMediaItem(
      id: 'e1',
      serverId: 'plex',
      kind: MediaKind.episode,
      grandparentId: 'show',
      parentIndex: 1,
      index: 1,
      durationMs: 1000000,
    );
    WatchStateNotifier().notifyProgress(item: episode, viewOffset: 300000, duration: 1000000);
    expect(ProgressRouting.overlay(episode).viewOffsetMs, 300000);
  });

  test('a profile that keeps its progress on the server hands everything back', () async {
    await bind();
    await bind(trackerLed: false);

    expect(controller.isActive, isFalse);
    expect(ProgressRouting.instance.serverKeepsWatchState, isTrue);
    expect(identical(ProgressRouting.overlay(other), other), isTrue);
  });

  test('another profile starts from its own state, not the last one\'s', () async {
    await bind();
    await controller.debugFlush();
    simkl.down = true;
    await bind(profile: 'ben');

    expect(ProgressRouting.overlay(film).isWatched, isFalse);
  });

  test('a position left here survives the app being closed before Simkl has it', () async {
    simkl.down = true;
    await bind();
    final episode = testMediaItem(
      id: 'e1',
      serverId: 'plex',
      kind: MediaKind.episode,
      grandparentId: 'show',
      parentIndex: 1,
      index: 1,
      durationMs: 1000000,
    );
    WatchStateNotifier().notifyProgress(item: episode, viewOffset: 420000, duration: 1000000);
    await controller.debugFlush();

    // Closed and opened again, Simkl still unreachable.
    controller.debugReset();
    controller.rootDirectory = () async => root;
    await bind();

    expect(ProgressRouting.overlay(episode).viewOffsetMs, 420000);
  });

  test('a failed first sync is tried again by itself, not left until a reconnect', () async {
    TrackerProgressController.retryDelays = const [Duration(milliseconds: 50)];
    simkl.down = true;
    await bind();
    expect(controller.syncFailed, isTrue);
    expect(ProgressRouting.overlay(film).isWatched, isFalse);

    simkl.down = false;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await controller.debugFlush();

    expect(controller.syncFailed, isFalse);
    expect(controller.lastSyncAt, isNotNull);
    expect(ProgressRouting.overlay(film).isWatched, isTrue);
  });

  test('"sync now" asks Simkl for everything again, not just what changed', () async {
    await bind();
    simkl.asked.clear();

    expect(await controller.syncNow(), isTrue);

    final everything = simkl.asked.where((uri) => uri.path == '/sync/all-items');
    expect(everything, isNotEmpty);
    expect(everything.every((uri) => !uri.queryParameters.containsKey('date_from')), isTrue);
    expect(server.asked, 2, reason: 'and every server for its ids once more');
  });

  test('"sync now" reports a Simkl that does not answer', () async {
    await bind();
    simkl.down = true;
    expect(await controller.syncNow(), isFalse);
    expect(controller.syncFailed, isTrue);
  });

  test('a server whose ids could not be read is left alone for a while, not asked at every refresh', () async {
    server.down = true;
    await bind();
    expect(server.asked, 1);

    await controller.refresh();
    await controller.refresh();
    expect(server.asked, 1, reason: 'a listing that ran into the timeout is not downloaded again at once');

    TrackerProgressController.indexRetryDelay = Duration.zero;
    server.down = false;
    await controller.refresh();
    expect(server.asked, 2);
    expect(ProgressRouting.overlay(film).isWatched, isTrue);
  });

  test('"sync now" asks a server whose ids could not be read at once', () async {
    server.down = true;
    await bind();
    server.down = false;

    await controller.syncNow();

    expect(server.asked, 2);
  });

  test('the same ids read again do not have every page fetch anew', () async {
    await bind();
    final revision = controller.revision.value;

    await withClock(Clock.fixed(clock.now().add(const Duration(hours: 2))), controller.refresh);

    expect(server.asked, 2, reason: 'the index had grown old and was read again');
    expect(controller.revision.value, revision);

    server.index = {...server.index, 'other': const ExternalIds(tmdb: 102)};
    await withClock(Clock.fixed(clock.now().add(const Duration(hours: 4))), controller.refresh);

    expect(server.asked, 3);
    expect(controller.revision.value, greaterThan(revision));
  });

  Future<void> restart() async {
    await controller.debugFlush();
    controller.debugReset();
    controller.rootDirectory = () async => root;
  }

  test('a start within the index\'s lifetime asks the server nothing', () async {
    await bind();
    await restart();

    await bind();

    expect(server.asked, 1, reason: 'the index kept on disk is still fresh');
    expect(ProgressRouting.overlay(film).isWatched, isTrue);
  });

  test('a later start asks only for what was added since; a week on, the whole index again', () async {
    server.newest = 1000;
    await bind();
    await restart();
    server.added = {'other': const ExternalIds(tmdb: 102)};
    server.newest = 1500;

    await withClock(Clock.fixed(clock.now().add(const Duration(hours: 2))), bind);

    expect(server.sinces, [null, 1000]);
    expect(controller.idsOf('plex', 'film')?.tmdb, 101, reason: 'what was known stays');
    expect(controller.idsOf('plex', 'other')?.tmdb, 102);

    await withClock(Clock.fixed(clock.now().add(const Duration(hours: 4))), controller.refresh);
    expect(server.sinces.last, 1500, reason: 'from the newest title read since');

    await withClock(Clock.fixed(clock.now().add(const Duration(days: 8))), controller.refresh);
    expect(server.sinces.last, isNull);
  });

  test('"sync now" reads every index whole', () async {
    server.newest = 1000;
    await bind();

    await controller.syncNow();

    expect(server.sinces, [null, null]);
  });

  test('a server that comes online after the start begins from its kept index', () async {
    await bind();
    await restart();
    final client = simkl.client();
    addTearDown(client.dispose);

    await controller.bind(profileId: 'anna', trackerLed: true, simkl: client, servers: const {});
    await controller.bind(profileId: 'anna', trackerLed: true, simkl: client, servers: {'plex': server});

    expect(server.asked, 1, reason: 'not read whole again for coming online late');
    expect(ProgressRouting.overlay(film).isWatched, isTrue);
  });

  test('playing does not have Simkl asked; stopping or a mark does', () async {
    await bind();
    final episode = testMediaItem(
      id: 'e1',
      serverId: 'plex',
      kind: MediaKind.episode,
      grandparentId: 'show',
      parentIndex: 1,
      index: 1,
      durationMs: 1000000,
    );

    // Playback leaves a position every 30 s; each one moves the echo on, so
    // it has to wait longer than that.
    WatchStateNotifier().notifyProgress(item: episode, viewOffset: 300000, duration: 1000000);
    expect(controller.debugEchoDelay, TrackerProgressController.positionEchoDelay);
    expect(TrackerProgressController.positionEchoDelay, greaterThan(const Duration(seconds: 30)));

    WatchStateNotifier().notifyWatched(item: other, isNowWatched: true);
    expect(controller.debugEchoDelay, TrackerProgressController.echoDelay);
  });
}
