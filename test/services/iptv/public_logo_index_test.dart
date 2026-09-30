import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/services/iptv/public_logo_index.dart';

/// Paths as the collection's file list names them.
const _paths = [
  'countries/germany/dazn1-de.png',
  'countries/germany/dmax-de.png',
  'countries/germany/hd/dmax-hd-de.png',
  'countries/austria/dmax-at.png',
  'countries/germany/sky-sport/sky-sport-mix-de.png',
  'countries/germany/sky-sport/hd/sky-sport-mix-hd-alt-de.png',
  'countries/germany/sky-sport/hd/sky-sport-mix-hd-de.png',
  'countries/germany/spiegel-tv-wissen-de.png',
  'countries/germany/national-geographic-de.png',
  'countries/germany/hd/national-geographic-hd-de.png',
  'countries/germany/das-erste-de.png',
  'countries/germany/allgau-tv-de.png',
  'countries/france/tf1-fr.png',
  'countries/germany/discovery-channel-de.png',
  'countries/germany/hd/discovery-channel-hd-de.png',
  'countries/germany/sky-sport/old/sky-sport-bundesliga-2-hd-de.png',
  'countries/germany/sky-sport/hd/sky-sport-bundesliga-2-hd-de.png',
  'countries/germany/sky-sport/sky-sport-bundesliga-2-de.png',
];

String _raw(String path) => '${PublicLogoIndex.rawBase}$path';

void main() {
  group('matching', () {
    final index = PublicLogoIndex()..debugUse(_paths);

    test('by exact name, quality words left off, the HD variant where the name says HD', () {
      expect(index.logoFor('DMAX HDraw'), _raw('countries/germany/hd/dmax-hd-de.png'));
      expect(index.logoFor('DMAX'), _raw('countries/germany/dmax-de.png'), reason: 'Germany before Austria');
      expect(
        index.logoFor('DAZN 1 HDraw'),
        _raw('countries/germany/dazn1-de.png'),
        reason: 'no HD variant: the plain one',
      );
      expect(index.logoFor('Sky Sport Mix HD'), _raw('countries/germany/sky-sport/hd/sky-sport-mix-hd-de.png'));
    });

    test('a provider\'s country prefix and umlauts do not stand in the way', () {
      expect(index.logoFor('DE: Das Erste'), _raw('countries/germany/das-erste-de.png'));
      expect(index.logoFor('Allgäu TV'), _raw('countries/germany/allgau-tv-de.png'));
    });

    test('a known short name finds the station it stands for', () {
      expect(index.logoFor('NatGeo HDraw'), _raw('countries/germany/hd/national-geographic-hd-de.png'));
      expect(index.logoFor('Discovery HDraw'), _raw('countries/germany/hd/discovery-channel-hd-de.png'));
    });

    test('Sky\'s old channel names find the renamed channel, never a retired mark', () {
      expect(
        index.logoFor('Sky Bundesliga 2 HDraw'),
        _raw('countries/germany/sky-sport/hd/sky-sport-bundesliga-2-hd-de.png'),
        reason: 'not the one in "old"',
      );
      expect(index.logoFor('Sky Bundesliga 2'), _raw('countries/germany/sky-sport/sky-sport-bundesliga-2-de.png'));
    });

    test('no near miss: a name the collection does not hold finds nothing', () {
      expect(index.logoFor('Spiegel TV HD'), isNull, reason: 'not Spiegel TV Wissen');
      expect(index.logoFor('ZDF'), isNull);
      expect(index.logoFor('TF1'), isNull, reason: 'France is not searched');
      expect(index.logoFor(''), isNull);
    });
  });

  group('the file list', () {
    late Directory root;
    var now = DateTime(2026, 9, 27);
    var requests = 0;
    var answer = 200;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('public_logos');
      now = DateTime(2026, 9, 27);
      requests = 0;
      answer = 200;
    });
    tearDown(() => root.delete(recursive: true));

    PublicLogoIndex fresh() => PublicLogoIndex(
      client: MockClient((request) async {
        requests++;
        if (answer != 200) return http.Response('', answer);
        return http.Response(
          jsonEncode({
            'tree': [
              for (final path in _paths) {'type': 'blob', 'path': path},
              {'type': 'tree', 'path': 'countries/germany'},
            ],
          }),
          200,
        );
      }),
      directory: () async => root,
      now: () => now,
    );

    test('is read once and kept for a week', () async {
      final first = fresh();
      await first.ensureLoaded();
      expect(first.ready.value, isTrue);
      expect(first.logoFor('DAZN 1'), isNotNull);
      expect(requests, 1);

      now = now.add(const Duration(days: 6));
      final second = fresh();
      await second.ensureLoaded();
      expect(second.logoFor('DAZN 1'), isNotNull);
      expect(requests, 1, reason: 'within the week, from disk');

      now = now.add(const Duration(days: 2));
      await fresh().ensureLoaded();
      expect(requests, 2, reason: 'a week on, read again');
    });

    test('an old list beats none when GitHub cannot be reached', () async {
      await fresh().ensureLoaded();
      now = now.add(const Duration(days: 30));
      answer = 503;

      final later = fresh();
      await later.ensureLoaded();
      expect(later.ready.value, isTrue);
      expect(later.logoFor('DMAX'), isNotNull);
    });

    test('with nothing stored and no answer, it asks again next time', () async {
      answer = 503;
      final index = fresh();
      await index.ensureLoaded();
      expect(index.ready.value, isFalse);
      answer = 200;
      await index.ensureLoaded();
      expect(index.ready.value, isTrue);
      expect(requests, 2);
    });
  });
}
