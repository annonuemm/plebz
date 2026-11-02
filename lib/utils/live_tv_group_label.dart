/// Country prefixes on IPTV group names.
///
/// Providers file every group under the country it serves — "DE • FreeTV/HD+",
/// "[UK] Sport", "FR: Cinéma" — which is useful in a playlist spanning a dozen
/// countries and pure repetition in one that does not. The prefix is what the
/// eye hits first in every chip of the group bar, so a viewer reads the same
/// two letters six times before reaching the word that tells them apart.
///
/// Dropping it is a display decision only: the raw group string stays the key
/// the channels are filtered, arranged and stored by, so nothing downstream
/// notices.
library;

/// Two-letter tokens that look like a country code and are not one. Three-letter
/// ones need no such list — they are only stripped when [_countryCodes3] knows
/// them.
const _notCountries2 = {'TV', 'HD', 'SD', 'FM', 'AM', 'XX', 'PP'};

/// Three-letter country forms seen in playlists, next to the ISO alpha-2 codes
/// handled by shape. Not exhaustive by design: an unknown token stays, which
/// costs a repeated word, while a wrong guess eats a group's actual name.
const _countryCodes3 = {
  'GER',
  'AUT',
  'SUI',
  'SWI',
  'USA',
  'CAN',
  'MEX',
  'BRA',
  'ARG',
  'GBR',
  'ENG',
  'IRL',
  'FRA',
  'ESP',
  'POR',
  'ITA',
  'NED',
  'NLD',
  'BEL',
  'LUX',
  'DEN',
  'DNK',
  'SWE',
  'NOR',
  'FIN',
  'ISL',
  'POL',
  'CZE',
  'SVK',
  'HUN',
  'ROU',
  'BUL',
  'GRE',
  'GRC',
  'TUR',
  'RUS',
  'UKR',
  'SRB',
  'CRO',
  'HRV',
  'BIH',
  'MKD',
  'SLO',
  'SVN',
  'ALB',
  'ARA',
  'UAE',
  'KSA',
  'EGY',
  'MAR',
  'TUN',
  'DZA',
  'ISR',
  'IND',
  'PAK',
  'CHN',
  'JPN',
  'KOR',
  'THA',
  'VIE',
  'PHI',
  'IDN',
  'MYS',
  'AUS',
  'NZL',
  'RSA',
  'NGA',
};

/// Separators a provider puts between the prefix and the name. The hyphen
/// stays last: anywhere else in a character class it would open a range.
const _separators = '•·|:/>~–—-';

/// `DE • Doku`, `DE- Doku`, `DE:Doku` — a code, then a separator.
final _barePrefix = RegExp('^([A-Za-z]{2,3})\\s*[$_separators]+\\s*(.+)\$');

/// `[DE] Doku`, `(DE) Doku`, `|DE| Doku` — the bracket does the separating, and
/// a further separator after it is optional.
final _bracketedPrefix = RegExp('^[\\[(|]\\s*([A-Za-z]{2,3})\\s*[\\])|]\\s*[$_separators]*\\s*(.+)\$');

bool _isCountryCode(String token) {
  // Mixed case is a word ("Doku", "Kid"), not a code.
  if (token != token.toUpperCase() && token != token.toLowerCase()) return false;
  final code = token.toUpperCase();
  return code.length == 2 ? !_notCountries2.contains(code) : _countryCodes3.contains(code);
}

/// [group] as it should read on screen.
///
/// A [customName] the user gave the group wins outright — they renamed it to
/// read what they want it to read, prefix rules included. Otherwise, with
/// [stripCountryPrefix] off — the default everywhere — the provider's name is
/// handed back untouched; with it on, one leading country code and the
/// separator behind it are removed. A name that is nothing but a code keeps
/// it, since an empty chip names nothing.
String liveTvGroupLabel(String group, {required bool stripCountryPrefix, String? customName}) {
  final named = customName?.trim();
  if (named != null && named.isNotEmpty) return named;
  if (!stripCountryPrefix) return group;
  final trimmed = group.trim();
  final match = _bracketedPrefix.firstMatch(trimmed) ?? _barePrefix.firstMatch(trimmed);
  if (match == null) return group;
  if (!_isCountryCode(match.group(1)!)) return group;
  final rest = match.group(2)!.trim();
  return rest.isEmpty ? group : rest;
}

/// [group]'s leading country code and the name behind it (Plebz, "Glas – v2"):
/// `DE • Doku` is `(country: 'DE', rest: 'Doku')`; a group with no code is
/// `(country: null, rest: group)`.
({String? country, String rest}) liveTvGroupCountrySplit(String group) {
  final trimmed = group.trim();
  final match = _bracketedPrefix.firstMatch(trimmed) ?? _barePrefix.firstMatch(trimmed);
  if (match == null || !_isCountryCode(match.group(1)!)) return (country: null, rest: trimmed);
  final rest = match.group(2)!.trim();
  return rest.isEmpty ? (country: null, rest: trimmed) : (country: match.group(1)!.toUpperCase(), rest: rest);
}

/// A country code as a heading over its groups: the country's German name
/// where it is one a provider commonly uses, else the code itself.
String liveTvCountryHeading(String code) => _countryNames[code.toUpperCase()] ?? code.toUpperCase();

const _countryNames = {
  'DE': 'Deutschland',
  'GER': 'Deutschland',
  'AT': 'Österreich',
  'AUT': 'Österreich',
  'CH': 'Schweiz',
  'SUI': 'Schweiz',
  'UK': 'Großbritannien',
  'GB': 'Großbritannien',
  'US': 'USA',
  'USA': 'USA',
  'NL': 'Niederlande',
  'BE': 'Belgien',
  'FR': 'Frankreich',
  'IT': 'Italien',
  'ES': 'Spanien',
  'PT': 'Portugal',
  'PL': 'Polen',
  'TR': 'Türkei',
  'DK': 'Dänemark',
  'SE': 'Schweden',
  'NO': 'Norwegen',
  'FI': 'Finnland',
  'GR': 'Griechenland',
  'HR': 'Kroatien',
  'RS': 'Serbien',
  'RO': 'Rumänien',
  'HU': 'Ungarn',
  'CZ': 'Tschechien',
  'RU': 'Russland',
  'UA': 'Ukraine',
  'AR': 'Arabisch',
  'IN': 'Indien',
  'CA': 'Kanada',
  'AU': 'Australien',
  'BR': 'Brasilien',
  'MX': 'Mexiko',
};

/// [names] with a trailing "RAW" (the provider's mark for an unprocessed
/// stream) left off each, where that leaves no two names the same.
List<String> liveTvWithoutRawMark(List<String> names) {
  final raw = RegExp(r'\s*[•·|:/\-–—]?\s*RAW$', caseSensitive: false);
  final stripped = [for (final name in names) name.replaceFirst(raw, '').trim()];
  final seen = <String, int>{};
  for (final name in stripped) {
    seen[name] = (seen[name] ?? 0) + 1;
  }
  return [
    for (var i = 0; i < names.length; i++)
      stripped[i].isEmpty || (seen[stripped[i]] ?? 0) > 1 || stripped[i] == names[i] ? names[i] : stripped[i],
  ];
}
