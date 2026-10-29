import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/providers/iptv_sources_provider.dart';
import 'package:plezy/services/iptv/iptv_live_tv_source.dart';
import 'package:plezy/services/iptv/iptv_source.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/prefs.dart';

const _m3u = IptvSource(id: 'a', name: 'Mein IPTV', kind: IptvSourceKind.m3u, playlistUrl: 'http://provider/list.m3u');

const _incomplete = IptvSource(id: 'b', name: 'Halb fertig', kind: IptvSourceKind.m3u);

IptvSourcesProvider _provider({String profileId = 'profile-1', String playlist = '#EXTM3U', int status = 200}) {
  final provider = IptvSourcesProvider(
    profileId: profileId,
    // Never let a test reach the network.
    buildSource: (source) =>
        IptvLiveTvSource(source, httpClient: MockClient((_) async => http.Response(playlist, status))),
  );
  addTearDown(provider.dispose);
  return provider;
}

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  test('starts empty', () async {
    final provider = _provider();
    await provider.ensureLoaded();

    expect(provider.sources, isEmpty);
    expect(provider.liveTvSources, isEmpty);
  });

  test('a saved source survives a restart', () async {
    final provider = _provider();
    await provider.save(_m3u);

    final reopened = _provider();
    await reopened.ensureLoaded();

    expect(reopened.sources.single.id, 'a');
    expect(reopened.sources.single.playlistUrl, 'http://provider/list.m3u');
  });

  test('refreshing by hand keeps the channels on show, and says when nothing came', () async {
    var status = 200;
    final provider = IptvSourcesProvider(
      profileId: 'profile-1',
      buildSource: (source) => IptvLiveTvSource(
        source,
        httpClient: MockClient(
          (_) async => http.Response(
            status == 200 ? '#EXTM3U\n#EXTINF:-1 tvg-id="ard",Das Erste\nhttp://provider/ard\n' : 'down',
            status,
          ),
        ),
      ),
    );
    addTearDown(provider.dispose);
    await provider.save(_m3u);
    final live = provider.liveTvForSourceId('a')!;
    expect(await live.fetchChannels(), hasLength(1));

    expect(await provider.refreshAll(), isTrue);

    status = 503;
    expect(await provider.refreshAll(), isFalse);
    // Before, the button dropped the stored copies first: Live TV showed a
    // loading bar, and with the provider down nothing at all.
    expect(await live.fetchChannels(), hasLength(1));
  });

  test('after saving, the channels are counted and the playlist guide is noticed', () async {
    final provider = _provider(
      playlist: '#EXTM3U url-tvg="http://provider/epg.xml"\n#EXTINF:-1 tvg-id="ard",Das Erste\nhttp://provider/ard\n',
    );
    await provider.save(_m3u);

    final loaded = await provider.loadChannelsOf('a');

    expect(loaded, (channels: 1, playlistGuide: true));
    expect(provider.usesPlaylistGuide('a'), isTrue);
  });

  test('a playlist that cannot be read counts no channels', () async {
    final provider = _provider(playlist: 'gone', status: 404);
    await provider.save(_m3u);

    expect(await provider.loadChannelsOf('a'), (channels: 0, playlistGuide: false));
    expect(await provider.loadChannelsOf('b'), isNull, reason: 'no such source');
  });

  test('saving the same id replaces rather than duplicates', () async {
    final provider = _provider();
    await provider.save(_m3u);
    await provider.save(_m3u.copyWith(name: 'Umbenannt'));

    expect(provider.sources, hasLength(1));
    expect(provider.sources.single.name, 'Umbenannt');
  });

  test('an incomplete source is stored but not offered as a backend', () async {
    // Half-finished configuration should survive a restart so the user can
    // finish it, without ever being queried.
    final provider = _provider();
    await provider.save(_incomplete);

    expect(provider.sources, hasLength(1));
    expect(provider.liveTvSources, isEmpty);
    expect(provider.liveTvForSourceId('b'), isNull);
  });

  test('a complete source becomes a Live TV backend', () async {
    final provider = _provider();
    await provider.save(_m3u);

    expect(provider.liveTvSources, hasLength(1));
    expect(provider.liveTvForSourceId('a'), isNotNull);
  });

  test('the backend instance is reused, so its caches are not thrown away', () async {
    final provider = _provider();
    await provider.save(_m3u);

    expect(identical(provider.liveTvForSourceId('a'), provider.liveTvForSourceId('a')), isTrue);
  });

  test('editing a source replaces its backend, since its URL may have changed', () async {
    final provider = _provider();
    await provider.save(_m3u);
    final before = provider.liveTvForSourceId('a');

    await provider.save(_m3u.copyWith(playlistUrl: 'http://provider/other.m3u'));

    expect(identical(before, provider.liveTvForSourceId('a')), isFalse);
  });

  test('removing a source drops it and its backend', () async {
    final provider = _provider();
    await provider.save(_m3u);

    await provider.remove('a');

    expect(provider.sources, isEmpty);
    expect(provider.liveTvForSourceId('a'), isNull);
  });

  test('sources belong to one profile', () async {
    final first = _provider();
    await first.save(_m3u);

    final other = _provider(profileId: 'profile-2');
    await other.ensureLoaded();

    expect(other.sources, isEmpty);
  });

  test('listeners hear about a change', () async {
    final provider = _provider();
    await provider.ensureLoaded();
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.save(_m3u);

    expect(notifications, greaterThan(0));
  });
}
