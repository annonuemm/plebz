import 'package:flutter_test/flutter_test.dart';
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
  });

  test('anything else is left to its own handler, or to nobody', () {
    expect(HomeLink.tryParse('plebz://play?content_id=plezy_srv_42'), isNull);
    expect(HomeLink.tryParse('plebz://live?channel=4.1'), isNull);
    expect(HomeLink.tryParse('plebz://open'), isNull, reason: 'no title named');
    expect(HomeLink.tryParse('plebz://now?id='), isNull);
    expect(HomeLink.tryParse('https://open?content_id=x'), isNull);
    expect(HomeLink.tryParse('plezy_srv_42'), isNull);
  });
}
