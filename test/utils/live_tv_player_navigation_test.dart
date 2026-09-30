import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/providers/iptv_sources_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/video_player_screen.dart';
import 'package:plezy/services/iptv/iptv_live_tv_source.dart';
import 'package:plezy/services/iptv/iptv_source.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/video_player_navigation.dart';
import 'package:plezy/utils/live_tv_player_navigation.dart';
import 'package:provider/provider.dart';

import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';

void main() {
  late MultiServerManager manager;
  late MultiServerProvider multiServer;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.bg);
    manager = MultiServerManager();
    multiServer = testMultiServerProvider(manager);
  });

  tearDown(() {
    multiServer.dispose();
    manager.dispose();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  Future<void> pumpLauncher(
    WidgetTester tester,
    LiveTvChannel channel, {
    IptvSourcesProvider? iptv,
    NavigatorObserver? observer,
  }) async {
    final launcher = MaterialApp(
      navigatorObservers: [?observer],
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => navigateToLiveTv(context, multiServer: multiServer, channel: channel, channels: [channel]),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: iptv == null
            ? launcher
            : ChangeNotifierProvider<IptvSourcesProvider>.value(value: iptv, child: launcher),
      ),
    );
  }

  test('scoped Live TV selection fails closed and unscoped selection retains fallback', () {
    final aDvr = LiveTvServerInfo(serverId: 'server-a', dvrKey: 'dvr-a');
    final aOtherDvr = LiveTvServerInfo(serverId: 'server-a', dvrKey: 'dvr-other');
    final bDvr = LiveTvServerInfo(serverId: 'server-b', dvrKey: 'dvr-b');

    multiServer.debugSetLiveTvServersForTesting([bDvr]);
    expect(
      liveTvServerInfoForChannel(
        multiServer,
        LiveTvChannel(key: 'channel-a', serverId: 'server-a', liveDvrKey: 'dvr-a'),
      ),
      isNull,
    );

    multiServer.debugSetLiveTvServersForTesting([aOtherDvr, bDvr]);
    expect(
      liveTvServerInfoForChannel(
        multiServer,
        LiveTvChannel(key: 'channel-a', serverId: 'server-a', liveDvrKey: 'dvr-a'),
      ),
      isNull,
      reason: 'an explicit DVR must not relax to another DVR on the same server',
    );
    expect(
      liveTvServerInfoForChannel(multiServer, LiveTvChannel(key: 'channel-a', serverId: 'server-a')),
      same(aOtherDvr),
    );

    multiServer.debugSetLiveTvServersForTesting([bDvr, aDvr]);
    expect(
      liveTvServerInfoForChannel(
        multiServer,
        LiveTvChannel(key: 'channel-a', serverId: 'server-a', liveDvrKey: 'dvr-a'),
      ),
      same(aDvr),
    );
    expect(liveTvServerInfoForChannel(multiServer, LiveTvChannel(key: 'legacy-channel')), same(bDvr));

    multiServer.debugSetLiveTvServersForTesting(const []);
    expect(liveTvServerInfoForChannel(multiServer, LiveTvChannel(key: 'legacy-channel')), isNull);
  });

  testWidgets('missing scoped server is not replaced by an online server', (tester) async {
    manager.debugRegisterClientForTesting(_TestClient(ServerId('server-b')));
    multiServer.debugSetLiveTvServersForTesting([LiveTvServerInfo(serverId: 'server-b', dvrKey: 'dvr-b')]);
    final channel = LiveTvChannel(key: 'channel-a', title: 'Channel A', serverId: 'server-a', liveDvrKey: 'dvr-a');
    await pumpLauncher(tester, channel);

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(find.byType(VideoPlayerScreen), findsNothing);
    expect(find.text('Сървърът за телевизия на живо не е наличен.'), findsOneWidget);
  });

  testWidgets('unavailable Live TV server error uses the active locale', (tester) async {
    final channel = LiveTvChannel(key: 'channel-1', title: 'Channel');
    await pumpLauncher(tester, channel);

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(find.text('Сървърът за телевизия на живо не е наличен.'), findsOneWidget);
    expect(find.text('Live TV server is not available.'), findsNothing);
  });

  testWidgets('disconnected Live TV server error uses the active locale', (tester) async {
    const serverId = 'server-1';
    final channel = LiveTvChannel(key: 'channel-1', title: 'Channel', serverId: serverId, liveDvrKey: 'dvr-1');
    multiServer.debugSetLiveTvServersForTesting([LiveTvServerInfo(serverId: serverId, dvrKey: 'dvr-1')]);
    await pumpLauncher(tester, channel);

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(find.text('Сървърът за телевизия на живо не е свързан.'), findsOneWidget);
    expect(find.text('Live TV server is not connected.'), findsNothing);
  });

  testWidgets('an IPTV channel opens the player although no server owns it', (tester) async {
    // The regression this guards: an IPTV channel has no entry in
    // `liveTvServers` and no client, so the server checks used to reject
    // every one of them before the player could resolve its playlist.
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();

    final iptv = IptvSourcesProvider(
      profileId: 'profile-1',
      buildSource: (source) =>
          IptvLiveTvSource(source, httpClient: MockClient((_) async => http.Response('#EXTM3U', 200))),
    );
    addTearDown(iptv.dispose);
    await iptv.save(
      const IptvSource(id: 'src', name: 'Mein IPTV', kind: IptvSourceKind.m3u, playlistUrl: 'http://provider/list.m3u'),
    );

    final observer = _RouteRecorder();
    final channel = LiveTvChannel(key: 'iptv:src:1', title: 'Das Erste', serverId: 'src', serverName: 'Mein IPTV');
    await pumpLauncher(tester, channel, iptv: iptv, observer: observer);

    await tester.tap(find.text('Open'));

    // Deliberately not pumped: the player route is asserted as pushed, not
    // built — building it would start a real media player.
    expect(observer.pushedRouteNames, contains(kVideoPlayerRouteName));
  });
}

/// Records pushed route names without letting the route build.
class _RouteRecorder extends NavigatorObserver {
  final pushedRouteNames = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushedRouteNames.add(route.settings.name);
}

class _TestClient implements MediaServerClient {
  _TestClient(this.serverId);

  @override
  final ServerId serverId;

  @override
  String? get serverName => 'Test server';

  @override
  MediaBackend get backend => MediaBackend.jellyfin;

  @override
  ServerCapabilities get capabilities => const ServerCapabilities(liveTv: true);

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
