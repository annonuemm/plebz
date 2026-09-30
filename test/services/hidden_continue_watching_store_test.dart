import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/services/hidden_continue_watching_store.dart';

import '../test_helpers/prefs.dart';

MediaItem _episode({String id = 'ep-1', int? positionMs, String serverId = 'server-1'}) => MediaItem.jellyfin(
  id: id,
  kind: MediaKind.episode,
  title: 'Episode',
  serverId: serverId,
  viewOffsetMs: positionMs,
  durationMs: 2400000,
);

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    HiddenContinueWatchingStore.debugReset();
    addTearDown(HiddenContinueWatchingStore.debugReset);
  });

  test('an item is only hidden once it has been hidden', () async {
    final store = HiddenContinueWatchingStore.forProfile('profile-1');
    await store.ensureLoaded();
    final item = _episode(positionMs: 600000);

    expect(store.isHidden(item), isFalse);

    await store.hide(item);

    expect(store.isHidden(item), isTrue);
  });

  test('picking the series back up brings the entry back', () async {
    final store = HiddenContinueWatchingStore.forProfile('profile-1');
    await store.hide(_episode(positionMs: 600000));

    // Same episode, watched ten minutes further on any client.
    expect(store.isHidden(_episode(positionMs: 1200000)), isFalse);
  });

  test('a couple of seconds of drift is not treated as viewing', () async {
    final store = HiddenContinueWatchingStore.forProfile('profile-1');
    await store.hide(_episode(positionMs: 600000));

    expect(store.isHidden(_episode(positionMs: 600000 + 2000)), isTrue);
    expect(store.isHidden(_episode(positionMs: 600000 - 2000)), isTrue);
    expect(store.isHidden(_episode(positionMs: 600000 + 60000)), isFalse);
  });

  test('a next-up episode that was never started stays hidden until it is played', () async {
    final store = HiddenContinueWatchingStore.forProfile('profile-1');
    await store.hide(_episode());

    expect(store.isHidden(_episode()), isTrue);
    expect(store.isHidden(_episode(positionMs: 300000)), isFalse);
  });

  test('hiding one entry leaves the others alone', () async {
    final store = HiddenContinueWatchingStore.forProfile('profile-1');
    await store.hide(_episode(id: 'ep-1', positionMs: 600000));

    expect(store.isHidden(_episode(id: 'ep-2', positionMs: 600000)), isFalse);
  });

  test('the same id on another server is a different entry', () async {
    final store = HiddenContinueWatchingStore.forProfile('profile-1');
    await store.hide(_episode(positionMs: 600000));

    expect(store.isHidden(_episode(positionMs: 600000, serverId: 'server-2')), isFalse);
  });

  test('hidden entries belong to one profile', () async {
    await HiddenContinueWatchingStore.forProfile('profile-1').hide(_episode(positionMs: 600000));

    final other = HiddenContinueWatchingStore.forProfile('profile-2');
    await other.ensureLoaded();

    expect(other.isHidden(_episode(positionMs: 600000)), isFalse);
  });

  test('hidden entries survive a restart', () async {
    await HiddenContinueWatchingStore.forProfile('profile-1').hide(_episode(positionMs: 600000));

    HiddenContinueWatchingStore.debugReset();
    final reopened = HiddenContinueWatchingStore.forProfile('profile-1');
    await reopened.ensureLoaded();

    expect(reopened.isHidden(_episode(positionMs: 600000)), isTrue);
  });

  group('visible', () {
    test('drops hidden entries and keeps the row order', () async {
      final store = HiddenContinueWatchingStore.forProfile('profile-1');
      await store.hide(_episode(id: 'ep-2', positionMs: 600000));

      final row = [
        _episode(id: 'ep-1', positionMs: 100000),
        _episode(id: 'ep-2', positionMs: 600000),
        _episode(id: 'ep-3', positionMs: 300000),
      ];

      expect(store.visible(row).map((item) => item.id), ['ep-1', 'ep-3']);
    });

    test('forgets an entry whose item has moved on, so the store cannot grow forever', () async {
      final store = HiddenContinueWatchingStore.forProfile('profile-1');
      await store.hide(_episode(positionMs: 600000));
      expect(store.hiddenCount, 1);

      store.visible([_episode(positionMs: 1200000)]);

      expect(store.hiddenCount, 0);
    });

    test('an empty store returns the row untouched', () async {
      final store = HiddenContinueWatchingStore.forProfile('profile-1');
      await store.ensureLoaded();
      final row = [_episode(id: 'ep-1', positionMs: 100000)];

      expect(store.visible(row), same(row));
    });
  });

  test('clear shows everything again', () async {
    final store = HiddenContinueWatchingStore.forProfile('profile-1');
    await store.hide(_episode(positionMs: 600000));

    await store.clear();

    expect(store.isHidden(_episode(positionMs: 600000)), isFalse);
    expect(store.hiddenCount, 0);
  });
}
