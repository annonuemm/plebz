import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/screens/media_detail/trailer_extras.dart';

PlexMediaItem _plex(String id, {String? subtype, String? trailerKey}) =>
    PlexMediaItem(id: id, kind: MediaKind.movie, title: id, subtype: subtype, trailerKey: trailerKey);

JellyfinMediaItem _jellyfin(String id, {Map<String, Object?>? raw}) =>
    JellyfinMediaItem(id: id, kind: MediaKind.movie, title: id, raw: raw);

void main() {
  group('which extra is the trailer', () {
    test("the server's own pick wins over the first trailer in the list", () {
      // Plex names a primary extra, and its own apps play that one.
      final extras = [_plex('900', subtype: 'trailer'), _plex('901', subtype: 'trailer')];
      final item = _plex('1', trailerKey: '/library/metadata/901');

      expect(primaryTrailerFor(item, extras)?.id, '901');
    });

    test('a named pick that is not in the list falls back to the first trailer', () {
      final extras = [_plex('900', subtype: 'featurette'), _plex('901', subtype: 'trailer')];
      final item = _plex('1', trailerKey: '/library/metadata/404');

      expect(primaryTrailerFor(item, extras)?.id, '901');
    });

    test('featurettes and deleted scenes are not trailers', () {
      final extras = [_plex('900', subtype: 'featurette'), _plex('901', subtype: 'deletedScene')];

      expect(primaryTrailerFor(_plex('1'), extras), isNull);
    });

    test("Jellyfin's spelling counts too, from either field", () {
      expect(
        primaryTrailerFor(_plex('1'), [
          _jellyfin('9', raw: {'ExtraType': 'Trailer'}),
        ])?.id,
        '9',
      );
      expect(
        primaryTrailerFor(_plex('1'), [
          _jellyfin('9', raw: {'Type': 'Trailer'}),
        ])?.id,
        '9',
      );
    });

    test('no extras at all is not an error', () {
      expect(primaryTrailerFor(_plex('1'), null), isNull);
      expect(primaryTrailerFor(_plex('1'), const []), isNull);
    });
  });
}
