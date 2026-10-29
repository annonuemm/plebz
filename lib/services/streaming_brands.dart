/// The streaming services the home screen can give a row of their own
/// (Plebz): every title of theirs that is on one of the viewer's servers.
///
/// "Theirs" is what the servers themselves say. A series names the network it
/// was made for (Plex's `network`, Jellyfin's studios), a film its studio, and
/// that is matched against the names below. Nothing is asked of a catalog
/// service: the row is about what one owns, and it costs no lookup per title.
/// The flip side is that it means *made by*, not *on offer at*: a licensed
/// series the service merely streams is not in its row, and films are patchy
/// because a film usually names its production company instead.
///
/// New ones go at the end: the stored layout names them by [shortcut], and
/// [BrandRowsLayout.decode] appends whatever a stored layout does not know.
enum StreamingBrand {
  netflix('netflix', 'Netflix', ['Netflix', 'Netflix Animation', 'Netflix Studios'], shownByDefault: true),
  prime('prime', 'Prime Video', [
    'Prime Video',
    'Amazon Prime Video',
    'Amazon',
    'Amazon Studios',
    'Amazon MGM Studios',
    'Amazon Freevee',
    'Freevee',
  ], shownByDefault: true),
  disney('disney', 'Disney+', ['Disney+', 'Disney Plus'], shownByDefault: true),
  hbo('hbo', 'HBO Max', ['HBO', 'HBO Max', 'Max', 'HBO Films', 'HBO Documentary Films'], shownByDefault: true),
  apple('apple', 'Apple TV', ['Apple TV', 'Apple TV+', 'Apple Original Films', 'Apple Studios'], shownByDefault: true),
  paramount('paramount', 'Paramount+', ['Paramount+', 'Paramount Plus', 'Paramount+ with Showtime']),
  sky('sky', 'Sky', [
    'Sky',
    'Sky Atlantic',
    'Sky One',
    'Sky 1',
    'Sky Max',
    'Sky Showcase',
    'Sky Deutschland',
    'Sky Studios',
    'Sky Cinema',
    'Sky Comedy',
    'Sky Crime',
    'Sky Witness',
    'Sky Documentaries',
  ]),
  magenta('magenta', 'MagentaTV', ['MagentaTV', 'Magenta TV']),
  rtlPlus('rtlplus', 'RTL+', ['RTL+', 'RTL Plus', 'TVNOW', 'TV Now']),
  joyn('joyn', 'Joyn', ['Joyn', 'Joyn Plus+', 'Joyn PLUS+']),
  hulu('hulu', 'Hulu', ['Hulu']),
  peacock('peacock', 'Peacock', ['Peacock']),
  crunchyroll('crunchyroll', 'Crunchyroll', ['Crunchyroll']);

  const StreamingBrand(this.shortcut, this.displayName, this.names, {this.shownByDefault = false});

  /// The stored form; never rename one.
  final String shortcut;

  /// The row's heading. A brand name, the same in every language.
  final String displayName;

  /// What servers call it — the service, its studio arms, its old names.
  /// Compared after [normalizeBrandName], so case and punctuation do not
  /// matter, but a name must match whole: "Disney Channel" is not Disney+.
  final List<String> names;

  /// Whether its row is on before the viewer has arranged anything.
  final bool shownByDefault;

  static StreamingBrand? fromShortcut(String shortcut) {
    for (final brand in values) {
      if (brand.shortcut == shortcut) return brand;
    }
    return null;
  }

  /// The brand a server's studio or network name stands for, or null.
  static StreamingBrand? matching(String serverName) {
    final wanted = normalizeBrandName(serverName);
    if (wanted.isEmpty) return null;
    return _byName[wanted];
  }

  static final Map<String, StreamingBrand> _byName = {
    for (final brand in values)
      for (final name in brand.names) normalizeBrandName(name): brand,
  };
}

/// Letters and digits only, with `+` and `&` spelled out: "Apple TV+" and
/// "apple tv plus" are one name, "Apple TV" another.
String normalizeBrandName(String name) =>
    name.toLowerCase().replaceAll('+', 'plus').replaceAll('&', 'and').replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Which brand rows the home screen shows and in which order — arranged the
/// way "Ligen verwalten" arranges the Sport page.
class BrandRowsLayout {
  const BrandRowsLayout({required this.order, required this.hidden});

  /// Every brand, in the viewer's order.
  final List<StreamingBrand> order;
  final Set<StreamingBrand> hidden;

  static final BrandRowsLayout standard = BrandRowsLayout.decode('');

  /// The ones on show, in order. Never empty: the last one cannot be hidden
  /// ([withHidden]) — switching the rows off is what the switch is for — and a
  /// stored layout that hides everything shows the first.
  List<StreamingBrand> get visible {
    final shown = [
      for (final brand in order)
        if (!hidden.contains(brand)) brand,
    ];
    return shown.isEmpty ? [order.first] : shown;
  }

  bool isHidden(StreamingBrand brand) => !visible.contains(brand);

  BrandRowsLayout withOrder(List<StreamingBrand> order) =>
      BrandRowsLayout(order: List.unmodifiable(order), hidden: hidden);

  /// [brand] hidden or shown; hiding the last one on show is refused.
  BrandRowsLayout withHidden(StreamingBrand brand, bool hide) {
    if (hide && visible.length == 1 && visible.single == brand) return this;
    final next = {...hidden};
    hide ? next.add(brand) : next.remove(brand);
    return BrandRowsLayout(order: order, hidden: Set.unmodifiable(next));
  }

  /// `netflix,prime,-sky,…` — the order, a minus before each hidden one.
  String encode() => [for (final brand in order) '${hidden.contains(brand) ? '-' : ''}${brand.shortcut}'].join(',');

  static BrandRowsLayout decode(String stored) {
    final order = <StreamingBrand>[];
    final hidden = <StreamingBrand>{};
    final known = <StreamingBrand>{};
    for (final raw in stored.split(',')) {
      final entry = raw.trim();
      if (entry.isEmpty) continue;
      final hide = entry.startsWith('-');
      final brand = StreamingBrand.fromShortcut(hide ? entry.substring(1) : entry);
      if (brand == null || !known.add(brand)) continue;
      order.add(brand);
      if (hide) hidden.add(brand);
    }
    for (final brand in StreamingBrand.values) {
      if (known.contains(brand)) continue;
      order.add(brand);
      if (!brand.shownByDefault) hidden.add(brand);
    }
    return BrandRowsLayout(order: List.unmodifiable(order), hidden: Set.unmodifiable(hidden));
  }
}

/// Where the brand rows stand on the home screen, as one block.
///
/// New ones go at the end: the stored value is the name.
enum BrandRowsPosition {
  /// Right under Continue Watching, ahead of the recommendation row.
  top,

  /// Under the recommendation row, ahead of the servers' own rows.
  afterRecommendations,

  /// After every row the servers send.
  bottom,
}
