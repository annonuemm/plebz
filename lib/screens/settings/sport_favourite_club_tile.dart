import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../services/settings_service.dart';
import '../../services/sport/sport_league_names.dart';
import '../../services/sport/sport_models.dart';
import '../../services/sport/sport_repository.dart';
import '../../utils/app_logger.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_builder.dart';
import '../sport/sport_league_view.dart' show SportCrest;

/// The viewer's club on the Sport page (Plebz): chosen from the clubs of the
/// three leagues this season, league by league, or none. Its game then
/// stands on a stage over the rest of its matchday.
class SportFavouriteClubTile extends StatelessWidget {
  const SportFavouriteClubTile({super.key, this.repository});

  /// For tests; the app asks the shared repository.
  final SportRepository? repository;

  @override
  Widget build(BuildContext context) {
    return SettingValueBuilder<int>(
      pref: PlebzPrefs.sportFavouriteClub,
      builder: (context, club, _) {
        final name = SettingsService.instance.read(PlebzPrefs.sportFavouriteClubName);
        return SettingNavigationTile(
          icon: Symbols.favorite_rounded,
          title: t.settings.sportFavouriteClub,
          subtitle: club == 0 || name.isEmpty ? t.settings.sportFavouriteClubDescription : name,
          onTap: () => unawaited(_choose(context, club)),
        );
      },
    );
  }

  Future<void> _choose(BuildContext context, int current) async {
    final clubs = await _clubs();
    if (!context.mounted) return;
    if (clubs.isEmpty) {
      showErrorSnackBar(context, t.settings.sportFavouriteClubLoadFailed);
      return;
    }
    final chosen = await showAdaptiveAppMenu<int>(
      context,
      title: t.settings.sportFavouriteClub,
      focusFirstItem: true,
      isScrollControlled: true,
      entries: [
        AppMenuItem<int>(value: 0, label: t.settings.sportFavouriteClubNone, selected: current == 0),
        for (final (league, teams) in clubs) ...[
          AppMenuHeader<int>(label: _leagueName(league)),
          for (final team in teams)
            AppMenuItem<int>(
              value: team.id,
              label: team.name,
              leading: SportCrest(team: team, size: 24),
              selected: team.id == current,
            ),
        ],
      ],
    );
    if (chosen == null) return;
    final team = [for (final (_, teams) in clubs) ...teams].where((team) => team.id == chosen).firstOrNull;
    final settings = SettingsService.instance;
    await settings.write(PlebzPrefs.sportFavouriteClubName, team?.name ?? '');
    await settings.write(PlebzPrefs.sportFavouriteClub, team?.id ?? 0);
  }

  /// This season's clubs of each league, by name; the table names them all,
  /// the matchday on show where there is no table yet.
  Future<List<(SportLeague, List<SportTeam>)>> _clubs() async {
    final repo = repository ?? SportRepository.instance;
    final result = <(SportLeague, List<SportTeam>)>[];
    // The German leagues only: a cup's clubs are theirs again, and a
    // European cup's mostly abroad.
    for (final league in SportLeague.values.where((league) => league.isDomestic)) {
      try {
        final now = await repo.current(league);
        if (now == null) continue;
        final rows = await repo.table(league, now.season) ?? const <SportTableRow>[];
        final byId = <int, SportTeam>{
          for (final row in rows) row.team.id: row.team,
          if (rows.isEmpty)
            for (final match in now.matches) ...{match.home.id: match.home, match.away.id: match.away},
        };
        final teams = byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
        if (teams.isNotEmpty) result.add((league, teams));
      } catch (error) {
        appLogger.d('Favourite club: no clubs for ${league.shortcut}', error: error);
      }
    }
    return result;
  }

  static String _leagueName(SportLeague league) => sportLeagueName(league);
}
