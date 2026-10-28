import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/deep_links/deep_link.dart';
import 'package:plezy/utils/home_link.dart';

void main() {
  test('the home-row links are read', () {
    expect((HomeLink.tryParse('plebz://open?content_id=plezy_srv_42') as PlebzOpenLink).contentId, 'plezy_srv_42');
    expect(HomeLink.tryParse('plebz://watchlist'), isA<PlebzWatchlistLink>());
    expect(HomeLink.tryParse('plebz://sport'), isA<PlebzSportLink>());
    expect(
      (HomeLink.tryParse('plebz://now?id=live_now%3Agame%3Abl1%3A9') as PlebzLiveNowLink).entryId,
      'live_now:game:bl1:9',
    );
    expect(
      (HomeLink.tryParse('plebz://reminder?key=iptv%7Ca%7C7%7C1761592500') as PlebzReminderLink).key,
      'iptv|a|7|1761592500',
    );
    expect(HomeLink.tryParse('plebz://reminder'), isNull, reason: 'no reminder named');
  });

  test('anything else is left to its own handler, or to nobody', () {
    expect(HomeLink.tryParse('plebz://play?content_id=plezy_srv_42'), isNull);
    expect(HomeLink.tryParse('plebz://live?channel=4.1'), isNull);
    expect(HomeLink.tryParse('plebz://open'), isNull, reason: 'no title named');
    expect(HomeLink.tryParse('plebz://now?id='), isNull);
    expect(HomeLink.tryParse('https://open?content_id=x'), isNull);
    expect(HomeLink.tryParse('plezy_srv_42'), isNull);
  });

  group('in the one link grammar (Plezy 2.25)', () {
    test('a tile link reaches the main screen as a HomeTileLink', () {
      final open = DeepLink.tryParse('plebz://open?content_id=plezy_srv_42');
      expect(open, isA<HomeTileLink>());
      expect(((open! as HomeTileLink).link as PlebzOpenLink).contentId, 'plezy_srv_42');
      expect((DeepLink.tryParse('plebz://watchlist')! as HomeTileLink).link, isA<PlebzWatchlistLink>());
      expect((DeepLink.tryParse('plebz://sport')! as HomeTileLink).link, isA<PlebzSportLink>());
      expect(((DeepLink.tryParse('plebz://now?id=x')! as HomeTileLink).link as PlebzLiveNowLink).entryId, 'x');
    });

    test('a bare open stays upstream\'s, and a tile link keeps a named profile', () {
      expect(DeepLink.tryParse('plebz://open'), isA<OpenLink>());
      expect(DeepLink.tryParse('plebz://sport?profile=Kids')!.profile, 'Kids');
    });

    test('written back, a tile link reads the same', () {
      for (final url in [
        'plebz://open?content_id=plezy_srv_42',
        'plebz://watchlist',
        'plebz://sport',
        'plebz://now?id=x',
        'plebz://reminder?key=k',
      ]) {
        final link = DeepLink.tryParse(url)! as HomeTileLink;
        final again = DeepLink.tryParse(link.toUri().toString())! as HomeTileLink;
        expect(again.link.runtimeType, link.link.runtimeType, reason: url);
        expect(again.toUri(), link.toUri(), reason: url);
      }
    });
  });
}
