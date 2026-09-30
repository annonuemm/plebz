import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_part.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/media_stream.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/services/catalog/library_copy_quality_loader.dart';

import '../../test_helpers/media_items.dart';
import '../../test_helpers/paged_fakes.dart';

/// Answers the two questions the loader asks, the way both backends do.
class _Server implements MediaServerClient {
  _Server({this.items = const {}, this.leaves = const {}, this.fails = false});

  final Map<String, MediaItem> items;
  final Map<String, List<MediaItem>> leaves;
  final bool fails;
  final calls = <String>[];

  @override
  ServerId get serverId => ServerId('server');

  @override
  Future<MediaItem?> fetchItem(String id) async {
    calls.add('item:$id');
    if (fails) throw StateError('unreachable');
    return items[id];
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPlayableDescendantsPage(String parentId, {int? start, int? size, abort}) async {
    calls.add('leaves:$parentId');
    if (fails) throw StateError('unreachable');
    return fakeLibraryPage(leaves[parentId] ?? const <MediaItem>[], start: start, size: size);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaVersion _uhdDolbyVision() => const MediaVersion(
  id: 'v',
  videoResolution: '4k',
  parts: [
    MediaPart(
      id: 'p',
      streams: [
        MediaStream(id: 'video', kind: MediaStreamKind.video, dolbyVision: true, dolbyVisionProfile: 8),
        MediaStream(id: 'audio', kind: MediaStreamKind.audio, codec: 'eac3', title: 'Atmos'),
      ],
    ),
  ],
);

void main() {
  setUp(LibraryCopyQualityLoader.clearForTesting);

  test('a film is measured by its own detail', () async {
    final film = testMediaItem(id: 'film', kind: MediaKind.movie, serverId: 'server');
    final server = _Server(
      items: {
        'film': testMediaItem(id: 'film', mediaVersions: [_uhdDolbyVision()]),
      },
    );
    final quality = await LibraryCopyQualityLoader(clientFor: (_) => server).load(film);

    expect(quality!.resolution, 2160);
    expect(quality.dynamicRange, 3);
    expect(quality.audio, 4, reason: 'Atmos');
    expect(server.calls, ['item:film']);
  });

  test('a series is measured by its first episode, and counts its episodes', () async {
    final series = testMediaItem(id: 'show', kind: MediaKind.show, serverId: 'server', leafCount: 19);
    final server = _Server(
      leaves: {
        'show': [testMediaItem(id: 'e1', kind: MediaKind.episode)],
      },
      items: {
        'e1': testMediaItem(id: 'e1', kind: MediaKind.episode, mediaVersions: [_uhdDolbyVision()]),
      },
    );
    final quality = await LibraryCopyQualityLoader(clientFor: (_) => server).load(series);

    expect(quality!.resolution, 2160);
    expect(quality.episodes, 19);
    expect(server.calls, ['leaves:show', 'item:e1'], reason: 'the lookup already said how many episodes');
  });

  test('where the lookup did not say how many episodes, the series itself is asked', () async {
    final series = testMediaItem(id: 'show', kind: MediaKind.show, serverId: 'server');
    final server = _Server(
      leaves: {
        'show': [testMediaItem(id: 'e1', kind: MediaKind.episode)],
      },
      items: {
        'e1': testMediaItem(id: 'e1', kind: MediaKind.episode, mediaVersions: [_uhdDolbyVision()]),
        'show': testMediaItem(id: 'show', kind: MediaKind.show, leafCount: 8),
      },
    );
    final quality = await LibraryCopyQualityLoader(clientFor: (_) => server).load(series);

    expect(quality!.episodes, 8);
  });

  test('an unreachable server or a missing client says nothing', () async {
    final film = testMediaItem(id: 'film', kind: MediaKind.movie, serverId: 'server');
    expect(await LibraryCopyQualityLoader(clientFor: (_) => _Server(fails: true)).load(film), isNull);
    expect(await LibraryCopyQualityLoader(clientFor: (_) => null).load(film), isNull);
  });

  test('an answer is kept, so the same copy is not asked twice', () async {
    final film = testMediaItem(id: 'film', kind: MediaKind.movie, serverId: 'server');
    final server = _Server(
      items: {
        'film': testMediaItem(id: 'film', mediaVersions: [_uhdDolbyVision()]),
      },
    );
    final loader = LibraryCopyQualityLoader(clientFor: (_) => server);

    await loader.load(film);
    await loader.load(film);
    expect(server.calls, ['item:film']);
  });
}
