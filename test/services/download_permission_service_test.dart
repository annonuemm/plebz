import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/services/download_permission_service.dart';

/// Answers the permission probe with [allowed], or throws when [fails].
class _PermissionClient implements MediaServerClient {
  _PermissionClient(String id, {this.allowed, this.fails = false}) : serverId = ServerId(id);

  @override
  final ServerId serverId;

  final bool? allowed;
  final bool fails;
  int probes = 0;

  @override
  Future<bool?> fetchDownloadsAllowed() async {
    probes++;
    if (fails) throw StateError('test: probe failed');
    return allowed;
  }

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _itemOn(String? serverId) =>
    MediaItem(id: 'item-1', backend: MediaBackend.plex, kind: MediaKind.movie, serverId: serverId);

void main() {
  final service = DownloadPermissionService.instance;

  setUp(service.debugReset);

  group('DownloadPermissionService', () {
    test('a server that has said nothing yet permits downloads', () {
      expect(service.allows('unknown-server'), isTrue);
    });

    test('an explicit refusal blocks that server', () async {
      await service.refreshFor(_PermissionClient('plex-1', allowed: false));

      expect(service.allows('plex-1'), isFalse);
      expect(service.hasBlockedServer, isTrue);
    });

    test('a silent server is not a refusal', () async {
      // An older build, or a backend without the notion. Restricting on
      // silence would strand setups whose server never answers.
      await service.refreshFor(_PermissionClient('plex-2', allowed: null));

      expect(service.allows('plex-2'), isTrue);
    });

    test('a failed probe is not a refusal either', () async {
      await service.refreshFor(_PermissionClient('plex-3', fails: true));

      expect(service.allows('plex-3'), isTrue);
    });

    test('permission granted later lifts the block', () async {
      await service.refreshFor(_PermissionClient('plex-4', allowed: false));
      expect(service.allows('plex-4'), isFalse);

      await service.refreshFor(_PermissionClient('plex-4', allowed: true));
      expect(service.allows('plex-4'), isTrue);
    });

    test('a server that drops off stops blocking', () async {
      // Otherwise a disconnect would outlive itself: reconnecting under an
      // account that may download would still find the old refusal.
      await service.refreshAll([_PermissionClient('gone', allowed: false)]);
      expect(service.allows('gone'), isFalse);

      await service.refreshAll([_PermissionClient('other', allowed: true)]);
      expect(service.allows('gone'), isTrue);
    });

    test('each server answers for itself', () async {
      await service.refreshAll([_PermissionClient('strict', allowed: false), _PermissionClient('open', allowed: true)]);

      expect(service.allows('strict'), isFalse);
      expect(service.allows('open'), isTrue);
    });

    test('an item is judged by the server it came from', () async {
      await service.refreshFor(_PermissionClient('strict', allowed: false));

      expect(service.allowsItem(_itemOn('strict')), isFalse);
      expect(service.allowsItem(_itemOn('open')), isTrue);
    });

    test('an item with no server is nobody\'s to forbid', () async {
      // A file already on the device, opened offline.
      await service.refreshFor(_PermissionClient('strict', allowed: false));

      expect(service.allowsItem(_itemOn(null)), isTrue);
    });

    test('listeners hear a change of answer, and only a change', () async {
      var notifications = 0;
      void count() => notifications++;
      service.addListener(count);
      addTearDown(() => service.removeListener(count));

      await service.refreshFor(_PermissionClient('plex-5', allowed: false));
      await service.refreshFor(_PermissionClient('plex-5', allowed: false));

      expect(notifications, 1);
    });
  });
}
