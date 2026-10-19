import '../../i18n/strings.g.dart';
import '../settings_service.dart';
import 'sport_models.dart';

/// What [league] is called on screen.
String sportLeagueName(SportLeague league) => switch (league) {
  SportLeague.bundesliga1 => t.sport.bundesliga1,
  SportLeague.bundesliga2 => t.sport.bundesliga2,
  SportLeague.liga3 => t.sport.liga3,
  SportLeague.championsLeague => t.sport.championsLeague,
  SportLeague.europaLeague => t.sport.europaLeague,
  SportLeague.dfbPokal => t.sport.dfbPokal,
};

final RegExp _numberedMatchday = RegExp(r'^\s*(\d+)\.\s*Spieltag\s*$');

/// What a matchday is called: "Spieltag 4" for a numbered one, the
/// provider's own name for a cup round ("Achtelfinale Hinspiele", "2. Runde").
/// [name] is the provider's; [order] the matchday's place in the season.
String sportMatchdayLabel(SportLeague league, int order, {String? name}) {
  if (league.isDomestic) return t.sport.matchday(n: order);
  final numbered = name == null ? null : _numberedMatchday.firstMatch(name);
  if (numbered != null) return t.sport.matchday(n: int.parse(numbered.group(1)!));
  return name == null || name.trim().isEmpty ? t.sport.matchday(n: order) : name.trim();
}

/// The viewer's arrangement of the competitions (see [SportLeagueLayout]).
SportLeagueLayout sportLeagueLayout() =>
    SportLeagueLayout.decode(SettingsService.instanceOrNull?.read(PlebzPrefs.sportLeagueLayout) ?? '');

/// The competitions on show, in the viewer's order.
List<SportLeague> visibleSportLeagues() => sportLeagueLayout().visible;
