import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/server_capabilities.dart';

void main() {
  group('favoriteActionAvailable', () {
    bool available({
      bool isOffline = false,
      bool isVideoContent = true,
      ServerCapabilities? capabilities = ServerCapabilities.jellyfin,
    }) =>
        favoriteActionAvailable(isOffline: isOffline, isVideoContent: isVideoContent, serverCapabilities: capabilities);

    test('a Jellyfin item offers the heart', () {
      expect(available(), isTrue);
    });

    test('Emby offers it too', () {
      expect(available(capabilities: ServerCapabilities.emby), isTrue);
    });

    test('Plex never does — it has no user favorites and its client throws', () {
      expect(available(capabilities: ServerCapabilities.plex), isFalse);
    });

    test('offline there is no server to tell', () {
      expect(available(isOffline: true), isFalse);
    });

    test('non-video items are out of scope', () {
      expect(available(isVideoContent: false), isFalse);
    });

    test('an unreachable server offers nothing', () {
      expect(available(capabilities: null), isFalse);
    });
  });
}
