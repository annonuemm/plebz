import 'dart:ui';

import 'sport_models.dart';

/// The colour a club is known by, for the tiles of the "Jetzt live" row
/// (Plebz): the one viewers recognise from shirts, flags and broadcasts, not
/// whatever a crest happens to be drawn in — St. Pauli is brown, though its
/// crest is mostly red. Null for a club whose colours are black and white,
/// and for one not listed; the tile then keeps its plain ground on that side.
///
/// By OpenLigaDB team id, which stays the same across seasons and leagues.
/// The clubs of the three leagues in 2025/26 and 2026/27; a club promoted
/// into them later needs a line here.
Color? clubColourFor(SportTeam team) => _clubColours[team.id] ?? _europeanClubColour(team);

/// The clubs of the European cups (Plebz), by name rather than id: their
/// OpenLigaDB ids are not known here, and their names are — in German, as
/// OpenLigaDB writes them ("Inter Mailand", "SSC Neapel"), and in short.
/// The longer names come first, so "Atlético Madrid" is not "Real Madrid".
/// Clubs in black and white (Juventus, Real Madrid, Newcastle, Besiktas,
/// PAOK, Qarabağ) stay out, as Elversberg does.
Color? _europeanClubColour(SportTeam team) {
  final names = '${_fold(team.name)} | ${_fold(team.shortName)}';
  for (final (key, colour) in _europeanClubColours) {
    if (names.contains(key)) return colour;
  }
  return null;
}

String _fold(String name) => name
    .toLowerCase()
    .replaceAll(RegExp('[áàâä]'), 'a')
    .replaceAll(RegExp('[éèê]'), 'e')
    .replaceAll(RegExp('[íì]'), 'i')
    .replaceAll(RegExp('[óòôöø]'), 'o')
    .replaceAll(RegExp('[úùü]'), 'u')
    .replaceAll('ç', 'c')
    .replaceAll('ş', 's')
    .replaceAll('ğ', 'g')
    .replaceAll('ı', 'i');

const _europeanClubColours = <(String, Color)>[
  // England
  ('manchester city', Color(0xFF6CABDD)),
  ('man city', Color(0xFF6CABDD)),
  ('man\'city', Color(0xFF6CABDD)),
  ('manchester united', Color(0xFFDA291C)),
  ('manu', Color(0xFFDA291C)),
  ('liverpool', Color(0xFFC8102E)),
  ('arsenal', Color(0xFFEF0107)),
  ('chelsea', Color(0xFF034694)),
  ('tottenham', Color(0xFF132257)),
  ('aston villa', Color(0xFF670E36)),
  ('nottingham', Color(0xFFDD0000)),
  ('crystal palace', Color(0xFF1B458F)),
  ('brighton', Color(0xFF0057B8)),
  // Spain
  ('atletico', Color(0xFFCB3524)),
  ('barcelona', Color(0xFFA50044)),
  ('villarreal', Color(0xFFFFE667)),
  // After Villarreal, which would otherwise be read as Aston Villa.
  ('villa', Color(0xFF670E36)),
  ('betis', Color(0xFF00954C)),
  ('athletic', Color(0xFFEE2523)),
  ('bilbao', Color(0xFFEE2523)),
  ('girona', Color(0xFFCD2534)),
  ('celta', Color(0xFF8AC3EE)),
  ('real sociedad', Color(0xFF0067B1)),
  // Italy
  ('inter', Color(0xFF0068A8)),
  ('ac mailand', Color(0xFFFB090B)),
  ('ac milan', Color(0xFFFB090B)),
  ('milan', Color(0xFFFB090B)),
  ('napoli', Color(0xFF12A0D7)),
  ('neapel', Color(0xFF12A0D7)),
  ('atalanta', Color(0xFF1E71B8)),
  ('as rom', Color(0xFF8E1F2F)),
  ('roma', Color(0xFF8E1F2F)),
  ('lazio', Color(0xFF87D8F7)),
  ('bologna', Color(0xFFA21C26)),
  ('fiorentina', Color(0xFF482E92)),
  ('como', Color(0xFF0A3D91)),
  // France
  ('paris', Color(0xFF004170)),
  ('psg', Color(0xFF004170)),
  ('marseille', Color(0xFF2FAEE0)),
  ('monaco', Color(0xFFE2001A)),
  ('lille', Color(0xFFE01E13)),
  ('lens', Color(0xFFE30613)),
  ('lyon', Color(0xFF1A3D8F)),
  ('nizza', Color(0xFFE30613)),
  ('nice', Color(0xFFE30613)),
  // Portugal
  ('benfica', Color(0xFFE83030)),
  ('porto', Color(0xFF003C8F)),
  ('sporting', Color(0xFF008057)),
  ('braga', Color(0xFFDC0028)),
  // Netherlands, Belgium
  ('ajax', Color(0xFFD2122E)),
  ('psv', Color(0xFFED1C24)),
  ('feyenoord', Color(0xFFE2001A)),
  ('az alkmaar', Color(0xFFDB0021)),
  ('brugge', Color(0xFF0067B1)),
  ('brugg', Color(0xFF0067B1)),
  ('union saint-gilloise', Color(0xFFFCD116)),
  ('union sg', Color(0xFFFCD116)),
  ('anderlecht', Color(0xFF4C2C92)),
  ('genk', Color(0xFF0E3B87)),
  // Scotland, Scandinavia
  ('celtic', Color(0xFF018749)),
  ('rangers', Color(0xFF1B458F)),
  ('kopenhagen', Color(0xFF1F3D8B)),
  ('copenhagen', Color(0xFF1F3D8B)),
  ('bodo', Color(0xFFFFE600)),
  ('glimt', Color(0xFFFFE600)),
  ('molde', Color(0xFF003F87)),
  ('viking', Color(0xFF0F4C99)),
  ('malmo', Color(0xFF7DBDE8)),
  // Austria, Switzerland
  ('salzburg', Color(0xFFD3003A)),
  ('young boys', Color(0xFFFFDD00)),
  ('basel', Color(0xFFE30613)),
  // Eastern Europe, Turkey, Greece, Cyprus, elsewhere
  ('galatasaray', Color(0xFFA90432)),
  ('fenerbahce', Color(0xFF002D72)),
  ('olympiakos', Color(0xFFD71920)),
  ('olympiacos', Color(0xFFD71920)),
  ('aek', Color(0xFFF7D417)),
  ('panathinaikos', Color(0xFF007A33)),
  ('slavia', Color(0xFFCE1126)),
  ('sparta prag', Color(0xFFA6192E)),
  ('plzen', Color(0xFF00529F)),
  ('shakhtar', Color(0xFFF68E1E)),
  ('schachtar', Color(0xFFF68E1E)),
  ('dynamo kiew', Color(0xFF1B4F9C)),
  ('roter stern', Color(0xFFDA291C)),
  ('crvena zvezda', Color(0xFFDA291C)),
  ('dinamo zagreb', Color(0xFF0047AB)),
  ('ferencvaros', Color(0xFF00843D)),
  ('kairat', Color(0xFFFFD700)),
  ('pafos', Color(0xFF00205B)),
  ('sabah', Color(0xFF1E4FA0)),
  ('legia', Color(0xFF00843D)),
  ('ludogorez', Color(0xFF00843D)),
];

/// Whether [team] is one of the German clubs listed here (Plebz): what a
/// European cup's Sport page puts first. The clubs in black and white count
/// too, though they have no colour.
bool isGermanClub(SportTeam team) => _clubColours.containsKey(team.id) || _blackAndWhite.contains(team.id);

/// SV 07 Elversberg, SC Verl, SSV Ulm 1846.
const _blackAndWhite = <int>{198, 114, 564};

const _clubColours = <int, Color>{
  // 1. Bundesliga
  65: Color(0xFFE32219), // 1. FC Köln
  80: Color(0xFFD4011D), // 1. FC Union Berlin
  81: Color(0xFFC3141E), // 1. FSV Mainz 05
  6: Color(0xFFE32221), // Bayer 04 Leverkusen
  7: Color(0xFFFDE100), // Borussia Dortmund
  87: Color(0xFF1F8F3F), // Borussia Mönchengladbach
  91: Color(0xFFE1000F), // Eintracht Frankfurt
  95: Color(0xFFBA3733), // FC Augsburg
  40: Color(0xFFDC052D), // FC Bayern München
  9: Color(0xFF004D9D), // FC Schalke 04
  100: Color(0xFF005CA9), // Hamburger SV
  1635: Color(0xFFDD0741), // RB Leipzig
  112: Color(0xFFE2001A), // SC Freiburg
  31: Color(0xFF005EA8), // SC Paderborn 07
  134: Color(0xFF1D9053), // SV Werder Bremen
  175: Color(0xFF1961B5), // TSG Hoffenheim
  16: Color(0xFFE32219), // VfB Stuttgart
  // 198 SV 07 Elversberg: black and white.

  // 2. Bundesliga
  199: Color(0xFFE30613), // 1. FC Heidenheim 1846
  76: Color(0xFFE2001A), // 1. FC Kaiserslautern
  78: Color(0xFF0062A8), // 1. FC Magdeburg
  79: Color(0xFFA51E36), // 1. FC Nürnberg
  83: Color(0xFF004E95), // DSC Arminia Bielefeld
  177: Color(0xFFFFD300), // Dynamo Dresden
  74: Color(0xFFFFCD00), // Eintracht Braunschweig
  93: Color(0xFFE30613), // Energie Cottbus
  98: Color(0xFF5C3C2C), // FC St. Pauli
  55: Color(0xFFD4001A), // Hannover 96
  54: Color(0xFF005CA9), // Hertha BSC
  104: Color(0xFF004D9D), // Holstein Kiel
  105: Color(0xFF00387D), // Karlsruher SC
  115: Color(0xFF009A44), // SpVgg Greuther Fürth
  118: Color(0xFF004E9E), // SV Darmstadt 98
  129: Color(0xFF005BA1), // VfL Bochum
  36: Color(0xFF5E2B7E), // VfL Osnabrück
  131: Color(0xFF65B32E), // VfL Wolfsburg
  // 3. Liga
  417: Color(0xFF00519E), // 1. FC Saarbrücken
  23: Color(0xFFFFED00), // Alemannia Aachen
  171: Color(0xFFD2001E), // FC Ingolstadt 04
  185: Color(0xFFE2001A), // Fortuna Düsseldorf
  1718: Color(0xFFE3000F), // Fortuna Köln
  102: Color(0xFF00519E), // Hansa Rostock
  181: Color(0xFFD7001D), // Jahn Regensburg
  107: Color(0xFF004F9F), // MSV Duisburg
  188: Color(0xFF00843D), // Preußen Münster
  109: Color(0xFFE30613), // Rot-Weiss Essen
  529: Color(0xFFD90F1E), // SG Sonnenhof Großaspach
  599: Color(0xFF005AA0), // SV Meppen
  553: Color(0xFF003D8F), // SV Waldhof Mannheim
  174: Color(0xFFE30613), // SV Wehen Wiesbaden
  2396: Color(0xFF1961B5), // TSG 1899 Hoffenheim II
  126: Color(0xFFE30613), // TSV Havelse
  184: Color(0xFFE32219), // VfB Stuttgart II
  2199: Color(0xFFD7001D), // Viktoria Köln
  398: Color(0xFFE30613), // Würzburger Kickers
  2952: Color(0xFF00843D), // 1. FC Schweinfurt 05
  66: Color(0xFF5B2C86), // Erzgebirge Aue
  125: Color(0xFF5DA9DD), // TSV 1860 München
  // 114 SC Verl, 564 SSV Ulm 1846: black and white.
};
