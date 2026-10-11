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
Color? clubColourFor(SportTeam team) => _clubColours[team.id];

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
