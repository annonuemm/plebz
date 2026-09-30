import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/year_filter.dart';
import '../../services/settings_service.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';

/// Release-year ranges for films and for series.
///
/// Two ranges rather than one because the years somebody wants from films are
/// rarely the years they want from series. Either end may be left empty,
/// which reads as "no limit that way" — "1985 to any" is the common case.
class YearFilterScreen extends StatefulWidget {
  const YearFilterScreen({super.key});

  @override
  State<YearFilterScreen> createState() => _YearFilterScreenState();
}

class _YearFilterScreenState extends State<YearFilterScreen> {
  /// One past the current year: libraries carry titles announced for next
  /// year, and a bound that excluded them would look like a bug.
  static int get _maxYear => DateTime.now().year + 1;

  SettingsService get _settings => SettingsService.instance;

  Future<void> _edit(IntPref pref, String label) async {
    final current = _settings.read(pref);
    final entered = await showTextInputDialog(
      context,
      title: label,
      labelText: label,
      initialValue: current > 0 ? '$current' : '',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
      // Empty is a valid answer: it is how an end is left open.
      allowEmpty: true,
      validator: (value) {
        if (value.trim().isEmpty) return null;
        final year = int.tryParse(value.trim());
        if (year == null || year < 1900 || year > _maxYear) return t.settings.yearFilterInvalid(max: _maxYear);
        return null;
      },
    );
    if (entered == null || !mounted) return;
    await _settings.write(pref, int.tryParse(entered.trim()) ?? 0);
    if (mounted) setState(() {});
  }

  String _rangeLabel(YearRange range) => range.isEmpty
      ? t.settings.yearFilterAnyYear
      : t.settings.yearFilterRangeLabel(
          from: range.from?.toString() ?? t.settings.yearFilterAnyYear,
          to: range.to?.toString() ?? t.settings.yearFilterAnyYear,
        );

  List<Widget> _rangeTiles({
    required IconData icon,
    required IntPref from,
    required IntPref to,
    required YearRange range,
  }) => [
    FocusableListTile(
      leading: AppIcon(icon, fill: 1),
      title: Text(t.settings.yearFilterFrom),
      subtitle: Text(_rangeLabel(range)),
      trailing: Text(
        _settings.read(from) > 0 ? '${_settings.read(from)}' : t.settings.yearFilterAnyYear,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      onTap: () => _edit(from, t.settings.yearFilterFrom),
    ),
    FocusableListTile(
      leading: const SizedBox(width: 24),
      title: Text(t.settings.yearFilterTo),
      trailing: Text(
        _settings.read(to) > 0 ? '${_settings.read(to)}' : t.settings.yearFilterAnyYear,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      onTap: () => _edit(to, t.settings.yearFilterTo),
    ),
  ];

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: Text(t.settings.yearFilter),
    children: [
      SettingsGroup(
        title: t.settings.yearFilterMovies,
        children: _rangeTiles(
          icon: Symbols.movie_rounded,
          from: SettingsService.yearFilterMovieFrom,
          to: SettingsService.yearFilterMovieTo,
          range: _settings.movieYearRange,
        ),
      ),
      SettingsGroup(
        title: t.settings.yearFilterShows,
        children: _rangeTiles(
          icon: Symbols.live_tv_rounded,
          from: SettingsService.yearFilterShowFrom,
          to: SettingsService.yearFilterShowTo,
          range: _settings.showYearRange,
        ),
      ),
      SettingsGroup(
        children: [
          SettingSwitchTile(
            pref: SettingsService.yearFilterBeyondLibraries,
            icon: Symbols.travel_explore_rounded,
            title: t.settings.yearFilterBeyondLibraries,
            subtitle: t.settings.yearFilterBeyondLibrariesDescription,
          ),
        ],
      ),
    ],
  );
}
