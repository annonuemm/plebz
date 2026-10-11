import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/models/catalog/catalog_person.dart';
import 'package:plezy/screens/catalog_person_screen.dart';

CatalogPersonCredit _credit(
  String ratingKey,
  String title,
  int? year, {
  MediaKind kind = MediaKind.movie,
  String group = 'actor',
}) => CatalogPersonCredit(
  item: CatalogItem(
    source: CatalogSourceId.plex,
    kind: kind,
    title: title,
    year: year,
    ids: CatalogItemIds(plex: ratingKey),
  ),
  group: group,
);

void main() {
  group('splitPersonTitles', () {
    final credits = [
      _credit('bb', 'Breaking Bad', 2008, kind: MediaKind.show),
      _credit('drive', 'Drive', 2011),
      _credit('godzilla', 'Godzilla', 2014),
      _credit('snl', 'Saturday Night Live', 1975, kind: MediaKind.show, group: 'appeared'),
      _credit('argo', 'Argo', 2012),
    ];

    test('a Plex copy is matched by the Discover id in its guid', () {
      final copy = MediaItem.plex(
        id: '101',
        kind: MediaKind.show,
        guid: 'plex://show/bb',
        title: 'Breaking Bad – Deutsch',
        year: 2008,
        serverId: 's1',
      );

      final split = splitPersonTitles(owned: [copy], credits: credits);

      expect([for (final o in split.owned) o.item], [copy]);
      expect(split.owned.single.credit?.item.title, 'Breaking Bad');
      expect([for (final c in split.others) c.item.title], ['Godzilla', 'Argo', 'Drive', 'Saturday Night Live']);
    });

    test('other servers match by kind, title or original title, and a year one out', () {
      final drive = MediaItem.jellyfin(id: 'j1', kind: MediaKind.movie, title: 'Drive', year: 2012, serverId: 'j');
      final godzilla = MediaItem.jellyfin(
        id: 'j2',
        kind: MediaKind.movie,
        title: 'Godzilla (Deutsch)',
        originalTitle: 'Godzilla',
        year: 2014,
        serverId: 'j',
      );
      final wrongKind = MediaItem.jellyfin(id: 'j3', kind: MediaKind.show, title: 'Argo', year: 2012, serverId: 'j');

      final split = splitPersonTitles(owned: [drive, godzilla, wrongKind], credits: credits);

      // Stable: of the two 2012 titles, the one the server sent first leads.
      expect([for (final o in split.owned) o.item], [godzilla, drive, wrongKind]);
      expect(split.owned.last.credit, isNull);
      expect([for (final c in split.others) c.item.title], ['Argo', 'Breaking Bad', 'Saturday Night Live']);
    });

    test('a title held on two servers shows once; episodes stay out', () {
      final plexCopy = MediaItem.plex(
        id: '1',
        kind: MediaKind.movie,
        guid: 'plex://movie/drive',
        title: 'Drive',
        year: 2011,
        serverId: 'p',
      );
      final jellyfinCopy = MediaItem.jellyfin(
        id: 'j',
        kind: MediaKind.movie,
        title: 'Drive',
        year: 2011,
        serverId: 'j',
      );
      final episode = MediaItem.plex(id: '2', kind: MediaKind.episode, title: 'Pilot', year: 2008, serverId: 'p');

      final split = splitPersonTitles(owned: [plexCopy, jellyfinCopy, episode], credits: credits);

      expect([for (final o in split.owned) o.item], [plexCopy]);
    });

    test('without a filmography the library titles stand alone', () {
      final copy = MediaItem.jellyfin(id: 'j', kind: MediaKind.movie, title: 'Drive', year: 2011, serverId: 'j');

      final split = splitPersonTitles(owned: [copy], credits: const []);

      expect([for (final o in split.owned) o.item], [copy]);
      expect(split.others, isEmpty);
    });
  });

  test('the tabs split films, series and guest appearances', () {
    bool inTab(PersonTitleTab tab, MediaKind kind, {bool appearance = false}) =>
        personTitleInTab(tab, kind: kind, appearance: appearance);

    expect(inTab(PersonTitleTab.all, MediaKind.show, appearance: true), isTrue);
    expect(inTab(PersonTitleTab.movies, MediaKind.movie), isTrue);
    expect(inTab(PersonTitleTab.movies, MediaKind.show), isFalse);
    expect(inTab(PersonTitleTab.shows, MediaKind.show), isTrue);
    // A talk show the person visited as themselves is not one of their series.
    expect(inTab(PersonTitleTab.shows, MediaKind.show, appearance: true), isFalse);
    expect(inTab(PersonTitleTab.appearances, MediaKind.show, appearance: true), isTrue);
    expect(inTab(PersonTitleTab.appearances, MediaKind.movie), isFalse);
  });
}
