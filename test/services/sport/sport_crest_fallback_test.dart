import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/screens/sport/sport_league_view.dart';
import 'package:plezy/services/sport/sport_crest_fallback.dart';
import 'package:plezy/services/sport/sport_models.dart';
import 'package:plezy/utils/fork_identity.dart';

const _leverkusen = SportTeam(id: 6, name: 'Bayer 04 Leverkusen', shortName: 'Leverkusen');

String _pageImages(String? source) => jsonEncode({
  'query': {
    'pages': {
      '1234': {
        'pageid': 1234,
        'title': 'Bayer 04 Leverkusen',
        if (source != null) 'thumbnail': {'source': source, 'width': 250, 'height': 250},
      },
    },
  },
});

void main() {
  group('SportCrestFallback', () {
    test("takes the club article's page image, without Wikipedia's tracking query", () async {
      late http.Request asked;
      final fallback = SportCrestFallback(
        client: MockClient((request) async {
          asked = request;
          return http.Response(
            _pageImages(
              'https://thumb.wikimedia.org/wikipedia/de/thumb/f/f7/Bayer_Leverkusen_Logo.svg/'
              '250px-Bayer_Leverkusen_Logo.svg.png?utm_source=de.wikipedia.org&utm_campaign=api',
            ),
            200,
          );
        }),
      );

      final url = await fallback.crestFor(_leverkusen);

      expect(
        url,
        'https://thumb.wikimedia.org/wikipedia/de/thumb/f/f7/Bayer_Leverkusen_Logo.svg/250px-Bayer_Leverkusen_Logo.svg.png',
      );
      expect(asked.url.host, 'de.wikipedia.org');
      expect(asked.url.queryParameters['titles'], 'Bayer 04 Leverkusen');
      expect(asked.url.queryParameters['pithumbsize'], '$crestThumbnailWidth');
      expect(asked.headers['User-Agent'], wikimediaUserAgent);
    });

    test('keeps an encoded file name encoded once', () {
      final url = SportCrestFallback.crestFromPageImages(
        jsonDecode(
          _pageImages(
            'https://thumb.wikimedia.org/wikipedia/commons/thumb/8/8d/FC_Bayern_M%C3%BCnchen_logo_%282024%29.svg/'
            '250px-FC_Bayern_M%C3%BCnchen_logo_%282024%29.svg.png?utm_source=x',
          ),
        ),
      );

      expect(
        url,
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/8/8d/FC_Bayern_M%C3%BCnchen_logo_%282024%29.svg/'
        '250px-FC_Bayern_M%C3%BCnchen_logo_%282024%29.svg.png',
      );
    });

    test('asks once per club, and again only after a lookup that found nothing', () async {
      var requests = 0;
      var answer = http.Response(_pageImages(null), 200);
      final fallback = SportCrestFallback(
        client: MockClient((_) async {
          requests++;
          return answer;
        }),
      );

      expect(await fallback.crestFor(_leverkusen), isNull);
      answer = http.Response('nope', 503);
      expect(await fallback.crestFor(_leverkusen), isNull);
      answer = http.Response(_pageImages('https://thumb.wikimedia.org/a/b/c.png'), 200);
      expect(await fallback.crestFor(_leverkusen), 'https://thumb.wikimedia.org/a/b/c.png');
      expect(await fallback.crestFor(_leverkusen), 'https://thumb.wikimedia.org/a/b/c.png');

      expect(requests, 3);
    });
  });

  group('SportCrest', () {
    test('a throttled or failing crest asks again a few times; a dead link goes to the fallback', () {
      expect(SportCrest.shouldRetry(429, 0), isTrue);
      expect(SportCrest.shouldRetry(null, 2), isTrue, reason: 'a timeout or a broken connection');
      expect(SportCrest.shouldRetry(429, 4), isFalse);
      expect(SportCrest.shouldRetry(404, 0), isFalse);
      expect(SportCrest.shouldRetry(410, 0), isFalse);
    });

    test('waits longer each time, with a little spread', () {
      expect(SportCrest.retryDelay(0), const Duration(milliseconds: 800));
      expect(SportCrest.retryDelay(1), const Duration(milliseconds: 1600));
      expect(SportCrest.retryDelay(3, spreadMs: 250), const Duration(milliseconds: 6650));
    });
  });
}
