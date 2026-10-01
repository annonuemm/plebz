import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/jellyfin_endpoint_discovery.dart';
import 'package:plezy/utils/network_locality.dart';

void main() {
  test('home network: private, loopback, link-local, CGNAT, unique-local, home suffixes', () {
    for (final host in [
      '192.168.1.10',
      '10.0.0.5',
      '172.16.4.2',
      '172.31.255.1',
      '100.64.0.1',
      '127.0.0.1',
      '169.254.10.10',
      '[fd00::1]',
      'fe80::1',
      '::1',
      'localhost',
      'nas',
      'jellyfin.local',
      'media.lan',
      'box.home.arpa',
      'tv.internal',
      'server.tail1234.ts.net',
    ]) {
      expect(isLocalOrPrivateHost(host), isTrue, reason: host);
    }
  });

  test('internet: public addresses and ordinary domain names', () {
    for (final host in ['8.8.8.8', '172.32.0.1', '100.128.0.1', '2001:4860:4860::8888', 'jf.example.com']) {
      expect(isLocalOrPrivateHost(host), isFalse, reason: host);
    }
  });

  test('plain HTTP is a warning only across the internet', () {
    expect(isPlainHttpOverInternet('http://jf.example.com:8096'), isTrue);
    expect(isPlainHttpOverInternet('https://jf.example.com'), isFalse);
    expect(isPlainHttpOverInternet('http://192.168.1.10:8096'), isFalse);
    expect(isPlainHttpOverInternet('http://nas:8096'), isFalse);
  });

  test('a bare Jellyfin host keeps every guess at home and only TLS on the internet', () {
    expect(JellyfinEndpointDiscovery.expandInputToBaseUrls('192.168.1.10'), contains('http://192.168.1.10:8096'));
    final internet = JellyfinEndpointDiscovery.expandInputToBaseUrls('jf.example.com');
    expect(internet, isNotEmpty);
    expect(internet.every((url) => url.startsWith('https://')), isTrue, reason: '$internet');
    expect(JellyfinEndpointDiscovery.expandInputToBaseUrls('http://jf.example.com:8096'), [
      'http://jf.example.com:8096',
    ], reason: 'typed by hand, taken as typed');
  });
}
