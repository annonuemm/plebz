import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/catalog/local_watchlist.dart';
import 'package:plezy/utils/external_ids.dart';

import '../../test_helpers/media_items.dart';
import '../../test_helpers/prefs.dart';

/// A provider that knows a title only once [knows] is set.
class _Source implements CatalogSource {
  @override
  CatalogSourceId get id => CatalogSourceId.plex;

  CatalogItemIds? knows;
  final asked = <String?>[];
  final added = <CatalogItemIds>[];

  @override
  Future<CatalogItemIds?> resolveItemIds(MediaKind kind, ExternalIds external, {String? title}) async {
    asked.add(title);
    return knows;
  }

  @override
  Future<void> addToWatchlist(MediaKind kind, CatalogItemIds ids, {String? title}) async => added.add(ids);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements MediaServerClient {
  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds(tvdb: 4711);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final show = testMediaItem(id: 'show-1', kind: MediaKind.show, title: 'Club der Reality Detektive', serverId: 's1');
  final start = DateTime(2026, 10, 4, 12);

  setUp(() {
    resetSharedPreferencesForTest();
    LocalWatchlist.debugReset();
  });

  test('a kept title is held, survives a fresh read, and stays with its profile', () async {
    final list = LocalWatchlist.forProfile('profile-a');
    await list.add(show, source: CatalogSourceId.plex);
    expect(list.holds(show), isTrue);

    LocalWatchlist.debugReset();
    final reread = LocalWatchlist.forProfile('profile-a');
    await reread.ensureLoaded();
    expect(reread.holds(show), isTrue);
    expect(reread.entries.single.title, 'Club der Reality Detektive');

    final other = LocalWatchlist.forProfile('profile-b');
    await other.ensureLoaded();
    expect(other.holds(show), isFalse);

    await reread.remove(show);
    expect(reread.holds(show), isFalse);
    final prefs = await BaseSharedPreferencesService.sharedCache();
    expect(prefs.getString('user_profile-a_${LocalWatchlist.baseKey}'), isNull);
  });

  test('the provider is asked again hourly, and a title it knows now is handed over', () async {
    final list = LocalWatchlist.forProfile('');
    final source = _Source();
    MediaServerClient? clientFor(String serverId) => serverId == 's1' ? _Client() : null;

    await withClock(Clock.fixed(start), () => list.add(show, source: CatalogSourceId.plex));

    // Just added: the press that kept it had asked already.
    await withClock(Clock.fixed(start.add(const Duration(minutes: 30))), () => list.promoteDue(source, clientFor));
    expect(source.asked, isEmpty);

    // Due, still unknown: asked once, and not again within the hour.
    await withClock(Clock.fixed(start.add(const Duration(hours: 1))), () => list.promoteDue(source, clientFor));
    await withClock(
      Clock.fixed(start.add(const Duration(hours: 1, minutes: 20))),
      () => list.promoteDue(source, clientFor),
    );
    expect(source.asked, ['Club der Reality Detektive']);
    expect(list.holds(show), isTrue);

    source.knows = const CatalogItemIds(plex: 'discover-9', tvdb: 4711);
    await withClock(
      Clock.fixed(start.add(const Duration(hours: 2, minutes: 30))),
      () => list.promoteDue(source, clientFor),
    );
    expect(source.added, [source.knows]);
    // From now on the provider answers membership.
    expect(list.holds(show), isFalse);
    expect(list.entries.single.isPromoted, isTrue);
  });

  test('a handed-over title stands in until the provider lists it, or a day has passed', () async {
    final list = LocalWatchlist.forProfile('');
    final source = _Source()..knows = const CatalogItemIds(plex: 'discover-9');
    await withClock(Clock.fixed(start), () async {
      await list.add(show, source: CatalogSourceId.plex);
      await list.promote(show, (source: source, ids: source.knows!));
    });

    final listed = [
      const CatalogItem(
        source: CatalogSourceId.plex,
        kind: MediaKind.show,
        title: 'Other',
        ids: CatalogItemIds(plex: 'x'),
      ),
    ].map((item) => item.toMediaItem()).toList();
    final stillShown = await withClock(
      Clock.fixed(start.add(const Duration(hours: 2))),
      () => list.shownBeside(CatalogSourceId.plex, listed),
    );
    expect(stillShown.single.itemId, 'show-1');

    final arrived = [
      ...listed,
      const CatalogItem(
        source: CatalogSourceId.plex,
        kind: MediaKind.show,
        title: 'Club der Reality Detektive',
        ids: CatalogItemIds(plex: 'discover-9'),
      ).toMediaItem(),
    ];
    final afterArrival = await withClock(
      Clock.fixed(start.add(const Duration(hours: 3))),
      () => list.shownBeside(CatalogSourceId.plex, arrived),
    );
    expect(afterArrival, isEmpty);
    expect(list.entries, isEmpty);
  });

  test('a handed-over title the provider never lists is let go after a day', () async {
    final list = LocalWatchlist.forProfile('');
    final source = _Source()..knows = const CatalogItemIds(plex: 'discover-9');
    await withClock(Clock.fixed(start), () async {
      await list.add(show, source: CatalogSourceId.plex);
      await list.promote(show, (source: source, ids: source.knows!));
    });

    final shown = await withClock(
      Clock.fixed(start.add(LocalWatchlist.promotedGrace)),
      () => list.shownBeside(CatalogSourceId.plex, const []),
    );
    expect(shown, isEmpty);
    expect(list.entries, isEmpty);
  });

  test('entries kept for another provider are not shown beside this one', () async {
    final list = LocalWatchlist.forProfile('');
    await list.add(show, source: CatalogSourceId.trakt);
    expect(await list.shownBeside(CatalogSourceId.plex, const []), isEmpty);
    expect((await list.shownBeside(CatalogSourceId.trakt, const [])).single.itemId, 'show-1');
  });

  test('a restore is picked up by the lists already in memory', () async {
    final list = LocalWatchlist.forProfile('');
    await list.ensureLoaded();
    expect(list.holds(show), isFalse);

    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(
      LocalWatchlist.baseKey,
      '[{"serverId":"s1","itemId":"show-1","backend":"plex","kind":"show","title":"Restored",'
      '"source":"plex","addedAt":${start.millisecondsSinceEpoch}}]',
    );
    LocalWatchlist.reloadAll();
    await list.ensureLoaded();
    expect(list.holds(show), isTrue);
  });
}
