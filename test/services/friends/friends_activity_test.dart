import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/catalog_item_ref.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/catalog/plex_catalog_source.dart';
import 'package:plezy/services/friends/friends_activity.dart';
import 'package:plezy/services/friends/plex_community_client.dart';
import 'package:plezy/services/plex_discover_client.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/friend_watch_badge.dart';

import '../../test_helpers/prefs.dart';

const _show = {'id': 'show1', 'type': 'show', 'title': 'Show'};

const _session = PlexDiscoverSession(accessToken: 'account-token', clientIdentifier: 'client-id');

Map<String, Object?> _entry({
  required String user,
  required String date,
  required String id,
  String type = 'movie',
  String title = 'Film',
  Map<String, Object?>? parent,
  Map<String, Object?>? grandparent,
}) => {
  'id': 'activity-$user-$id-$date',
  'date': date,
  'metadataItem': {'id': id, 'type': type, 'title': title, 'index': 3, 'parent': ?parent, 'grandparent': ?grandparent},
  'userV2': {'id': user},
};

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: const {'content-type': 'application/json'});

/// community.plex.tv answering the friend list and the feed, and Discover
/// answering each title by its id.
class _Plex {
  final requests = <Map<String, dynamic>>[];
  final headers = <Map<String, String>>[];
  List<Map<String, Object?>> friends = [
    {
      'user': {'id': 'anna', 'username': 'anna77', 'displayName': 'Anna', 'avatar': 'https://plex.tv/users/a/avatar'},
    },
    {
      'user': {'id': 'ben', 'username': 'ben', 'displayName': '', 'avatar': 'http://insecure/avatar'},
    },
  ];
  List<Map<String, Object?>> feed = [];
  Map<String, List<Map<String, Object?>>> perTitle = {};

  late final community = MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    requests.add(body);
    headers.add(request.headers);
    return switch (body['operationName']) {
      'PlebzFriends' => _json({
        'data': {'allFriendsV2': friends},
      }),
      'PlebzFriendsActivity' => _json({
        'data': {
          'activityFeed': {
            'nodes': feed,
            'pageInfo': {'hasNextPage': false, 'endCursor': null},
          },
        },
      }),
      'PlebzTitleActivity' => _json({
        'data': {
          'activityFeed': {
            'nodes': perTitle[(body['variables'] as Map)['metadataID']] ?? const [],
            'pageInfo': {'hasNextPage': false},
          },
        },
      }),
      _ => _json({
        'errors': [
          {'message': 'unknown'},
        ],
      }),
    };
  });

  final discover = MockClient((request) async {
    final id = request.url.pathSegments.last;
    final isShow = id.startsWith('show');
    return _json({
      'MediaContainer': {
        'Metadata': [
          {
            'ratingKey': id,
            'guid': 'plex://${isShow ? 'show' : 'movie'}/$id',
            'type': isShow ? 'show' : 'movie',
            'title': 'Title $id',
            'year': 2024,
            'thumb': 'https://metadata-static.plex.tv/$id.jpg',
          },
        ],
      },
    });
  });

  FriendsActivity activity({DateTime? now}) {
    final friends = FriendsActivity(
      clientFor: (session) => PlexCommunityClient(session, httpClient: community),
      now: now == null ? null : () => now,
    );
    friends.bind(
      session: _session,
      source: PlexCatalogSource(PlexDiscoverClient(_session, httpClient: discover)),
    );
    return friends;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    await LocaleSettings.setLocale(AppLocale.de);
    await initializeDateFormatting('de');
  });

  tearDown(() => LocaleSettings.setLocale(AppLocale.en));

  group('PlexCommunityClient', () {
    test('asks with the account token and reads friends and their watches', () async {
      final plex = _Plex()
        ..feed = [
          _entry(user: 'anna', date: '2026-10-30T20:15:00Z', id: 'movie1', title: 'Nordlicht'),
          _entry(
            user: 'ben',
            date: '2026-10-29T18:00:00Z',
            id: 'episode9',
            type: 'episode',
            title: 'Folge',
            parent: {'id': 'season2', 'type': 'season', 'index': 2},
            grandparent: {'id': 'show7', 'type': 'show', 'title': 'Die Werft'},
          ),
          // Without who, when or what, an entry says nothing a row can use.
          {
            'id': 'x',
            'date': 'not a date',
            'metadataItem': {'id': 'm', 'type': 'movie', 'title': 'T'},
            'userV2': {'id': 'anna'},
          },
          {
            'id': 'y',
            'date': '2026-10-30T20:15:00Z',
            'userV2': {'id': 'anna'},
          },
          // An episode whose show is unknown has no title to open.
          _entry(user: 'anna', date: '2026-10-30T20:15:00Z', id: 'episode1', type: 'episode'),
        ];
      final client = PlexCommunityClient(_session, httpClient: plex.community);

      final friends = await client.friends();
      expect([for (final f in friends) f.name], ['Anna', 'ben'], reason: 'the user name where no display name');
      expect(friends.first.avatarUrl, 'https://plex.tv/users/a/avatar');
      expect(friends.last.avatarUrl, isNull, reason: 'only an https picture is drawn');
      expect(plex.headers.first['x-plex-token'] ?? plex.headers.first['X-Plex-Token'], 'account-token');

      final entries = await client.recentActivity();
      expect(entries, hasLength(2));
      expect(entries.first.titleId, 'movie1');
      expect(entries.last.titleId, 'show7');
      expect(entries.last.season, 2);
      expect(entries.last.episode, 3);
    });

    test('a GraphQL error without data is an error', () async {
      final client = PlexCommunityClient(
        _session,
        httpClient: MockClient(
          (_) async => _json({
            'errors': [
              {'message': 'Cannot query field'},
            ],
          }),
        ),
      );
      await expectLater(client.friends(), throwsA(isA<PlexCommunityException>()));
    });
  });

  group('FriendsActivity', () {
    test('turns the feed into titles: one line per friend, newest first, strangers left out', () async {
      final plex = _Plex()
        ..feed = [
          _entry(user: 'anna', date: '2026-10-30T20:00:00Z', id: 'movie1'),
          _entry(user: 'anna', date: '2026-10-20T20:00:00Z', id: 'movie1'),
          _entry(
            user: 'ben',
            date: '2026-10-31T09:00:00Z',
            id: 'episode1',
            type: 'episode',
            parent: {'id': 'season1', 'index': 1},
            grandparent: {'id': 'show1', 'title': 'Show'},
          ),
          _entry(user: 'ben', date: '2026-10-28T09:00:00Z', id: 'movie1'),
          // The account's own watches, and anyone not a friend.
          _entry(user: 'me', date: '2026-10-31T10:00:00Z', id: 'movie2'),
        ];
      final friends = plex.activity();

      await friends.ensureFeed();

      expect([for (final title in friends.titles) title.item.ids.plex], ['show1', 'movie1']);
      final film = friends.titles.last;
      expect([for (final w in film.watches) w.friend.name], ['Anna', 'ben']);
      expect(film.watches.first.at, DateTime.parse('2026-10-30T20:00:00Z').toLocal());
      expect(friends.titles.first.item.kind, MediaKind.show);
      expect([for (final f in friends.activeFriends) f.name], ['ben', 'Anna']);

      final tile = film.toMediaItem();
      expect(friendWatchOf(tile)?.name, 'Anna');
      expect(tile.isCatalogItem, isTrue, reason: 'opens as Explore opens it');
    });

    test('keeps the feed for a while instead of asking on every visit', () async {
      final plex = _Plex()..feed = [_entry(user: 'anna', date: '2026-10-30T20:00:00Z', id: 'movie1')];
      var now = DateTime(2026, 10, 31, 12);
      final friends =
          FriendsActivity(
            clientFor: (session) => PlexCommunityClient(session, httpClient: plex.community),
            now: () => now,
          )..bind(
            session: _session,
            source: PlexCatalogSource(PlexDiscoverClient(_session, httpClient: plex.discover)),
          );

      await friends.ensureFeed();
      await friends.ensureFeed();
      expect(plex.requests.where((r) => r['operationName'] == 'PlebzFriendsActivity'), hasLength(1));

      now = now.add(FriendsActivity.feedLifetime);
      await friends.ensureFeed();
      expect(plex.requests.where((r) => r['operationName'] == 'PlebzFriendsActivity'), hasLength(2));
    });

    test('says nothing when switched off, and nothing for a profile on a shared account', () async {
      final plex = _Plex()..feed = [_entry(user: 'anna', date: '2026-10-30T20:00:00Z', id: 'movie1')];
      final friends = plex.activity();
      await friends.ensureFeed();
      expect(friends.titles, isNotEmpty);

      await SettingsService.instance.write(PlebzPrefs.showFriendsActivity, false);
      expect(friends.isEnabled, isFalse);
      expect(friends.titles, isEmpty);
      expect(await friends.watchersOf('movie1'), isEmpty);

      await SettingsService.instance.write(PlebzPrefs.showFriendsActivity, true);
      friends.bind(session: _session, source: friends.boundSource, setAside: true);
      expect(friends.isAvailable, isFalse, reason: "the account's friends are not the viewer's");
      expect(friends.titles, isEmpty);
    });

    test('names the friends who watched one title, each once', () async {
      final plex = _Plex()
        ..perTitle = {
          'show1': [
            _entry(user: 'ben', date: '2026-10-29T09:00:00Z', id: 'e2', type: 'episode', grandparent: _show),
            _entry(user: 'anna', date: '2026-10-30T09:00:00Z', id: 'e1', type: 'episode', grandparent: _show),
            _entry(user: 'ben', date: '2026-10-20T09:00:00Z', id: 'e1', type: 'episode', grandparent: _show),
          ],
        };
      final friends = plex.activity();

      final watches = await friends.watchersOf('show1');

      expect([for (final w in watches) w.friend.name], ['Anna', 'ben']);
      expect(
        (plex.requests.last['variables'] as Map)['metadataID'],
        'show1',
        reason: 'the show with its episodes, in one question',
      );
    });

    test("reads Discover's id from a Plex title's guid", () {
      expect(FriendsActivity.discoverIdFromGuid('plex://movie/5d776b59ad5437001f79c6f8'), '5d776b59ad5437001f79c6f8');
      expect(FriendsActivity.discoverIdFromGuid('plex://show/abc123'), 'abc123');
      expect(FriendsActivity.discoverIdFromGuid('plex://episode/abc123'), isNull);
      expect(FriendsActivity.discoverIdFromGuid('com.plexapp.agents.imdb://tt1'), isNull);
      expect(FriendsActivity.discoverIdFromGuid(null), isNull);
    });

    test('says when in words: heute, gestern, a weekday, a date', () {
      final now = DateTime(2026, 10, 31, 12);
      expect(friendWatchWhen(DateTime(2026, 10, 31, 8), now: now), 'heute');
      expect(friendWatchWhen(DateTime(2026, 10, 30, 23), now: now), 'gestern');
      expect(friendWatchWhen(DateTime(2026, 10, 27, 20), now: now), 'Di');
      expect(friendWatchWhen(DateTime(2026, 10, 2, 20), now: now), '2. Okt.');
    });
  });

  for (final variant in const [AppThemeVariant.standard, AppThemeVariant.glas, AppThemeVariant.flach]) {
    testWidgets('the poster wears the friend and when, ${variant.name}', (tester) async {
      await _pumpBadge(tester, monoTheme(MonoPalette.dark, variant: variant));
    });
  }

  testWidgets('the poster wears the friend and when', (tester) async {
    final item = MediaItem(id: 'catalog:plex:x', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Nordlicht')
        .copyWith(
          raw: {
            friendWatchRawKey: {'name': 'Anna', 'initial': 'A', 'at': DateTime.now().millisecondsSinceEpoch},
          },
        );
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: SizedBox(width: 180, height: 270, child: Stack(children: [?FriendWatchBadge.forItem(item)])),
      ),
    );
    expect(find.text('Anna · heute'), findsOneWidget);
    expect(find.text('A'), findsOneWidget, reason: 'the initial, where Plex gives no picture');

    final plain = MediaItem(id: 'x', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Plain');
    expect(FriendWatchBadge.forItem(plain), isNull);
  });
}

Future<void> _pumpBadge(WidgetTester tester, ThemeData theme) async {
  final item = MediaItem(id: 'catalog:plex:x', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Nordlicht')
      .copyWith(
        raw: {
          friendWatchRawKey: {
            'name': 'Anna Katharina Lindqvist',
            'initial': 'A',
            'at': DateTime.now().millisecondsSinceEpoch,
          },
        },
      );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: SizedBox(width: 120, height: 180, child: Stack(children: [?FriendWatchBadge.forItem(item)])),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull, reason: 'a long name ellipsizes instead of overflowing');
  expect(find.textContaining('Anna Katharina'), findsOneWidget);
}
