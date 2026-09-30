import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../focus/focusable_text_field.dart';
import '../../services/settings_service.dart';
import '../../i18n/strings.g.dart';
import '../../providers/iptv_sources_provider.dart';
import '../../services/iptv/iptv_catchup.dart';
import '../../services/iptv/iptv_source.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/setting_tile.dart';
import 'settings_utils.dart';
import '../../widgets/settings_section.dart';

/// Manage the profile's IPTV sources — playlists and Xtream panels.
///
/// A source configured here appears in Live TV next to any Plex or Jellyfin
/// server, with its channels and guide. It cannot record: that needs a server
/// doing the recording, which a playlist is not.
class IptvSettingsScreen extends StatelessWidget {
  const IptvSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvSourcesProvider>();
    final sources = provider.sources;

    return FocusedScrollScaffold(
      title: Text(t.iptv.title),
      slivers: [
        SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                t.iptv.hubSubtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            if (sources.isNotEmpty) ...[
              SettingsGroup(
                children: [
                  for (final source in sources)
                    FocusableListTile(
                      leading: AppIcon(
                        source.kind == IptvSourceKind.xtream ? Symbols.dns_rounded : Symbols.playlist_play_rounded,
                        fill: 1,
                      ),
                      title: Text(source.name),
                      subtitle: Text(_subtitleFor(source)),
                      trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
                      onTap: () => unawaited(_edit(context, source)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (sources.isNotEmpty) ...[
              SettingsGroup(
                children: [
                  SettingSwitchTile(
                    pref: SettingsService.iptvMergeDuplicateChannels,
                    icon: Symbols.merge_rounded,
                    title: t.iptv.mergeDuplicatesLabel,
                    subtitle: t.iptv.mergeDuplicatesDescription,
                  ),
                  SettingSwitchTile(
                    pref: SettingsService.iptvHideGroupCountryPrefix,
                    icon: Symbols.label_off_rounded,
                    title: t.iptv.hideGroupCountryPrefixLabel,
                    subtitle: t.iptv.hideGroupCountryPrefixDescription,
                  ),
                  SettingSwitchTile(
                    pref: SettingsService.iptvPublicLogoFallback,
                    icon: Symbols.image_search_rounded,
                    title: t.iptv.publicLogoFallbackLabel,
                    subtitle: t.iptv.publicLogoFallbackDescription,
                  ),
                  SettingSwitchTile(
                    pref: SettingsService.iptvBrightenDarkLogos,
                    icon: Symbols.brightness_high_rounded,
                    title: t.iptv.brightenDarkLogosLabel,
                    subtitle: t.iptv.brightenDarkLogosDescription,
                  ),
                  SettingSelectionTile<int>(
                    pref: SettingsService.iptvRefreshIntervalDays,
                    icon: Symbols.update_rounded,
                    title: t.iptv.refreshIntervalLabel,
                    subtitleBuilder: _refreshIntervalLabel,
                    options: [
                      for (final days in const [1, 2, 3, 7])
                        DialogOption(value: days, title: _refreshIntervalLabel(days)),
                    ],
                  ),
                  // The interval above answers "how often at the latest"; a
                  // provider that changed its line-up this morning is the case
                  // it cannot answer. Dropping the stored copies is the whole
                  // of it — the next read finds nothing on disk and fetches.
                  FocusableListTile(
                    leading: const AppIcon(Symbols.refresh_rounded, fill: 1),
                    title: Text(t.iptv.refreshNowLabel),
                    subtitle: Text(t.iptv.refreshNowDescription),
                    onTap: () {
                      provider.refreshAll();
                      showSuccessSnackBar(context, t.iptv.refreshNowDone);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            SettingsGroup(
              children: [
                FocusableListTile(
                  leading: const AppIcon(Symbols.playlist_add_rounded, fill: 1),
                  title: Text(t.iptv.addPlaylist),
                  subtitle: Text(t.iptv.addPlaylistDescription),
                  onTap: () => unawaited(_edit(context, null, kind: IptvSourceKind.m3u)),
                ),
                FocusableListTile(
                  leading: const AppIcon(Symbols.add_link_rounded, fill: 1),
                  title: Text(t.iptv.addXtream),
                  subtitle: Text(t.iptv.addXtreamDescription),
                  onTap: () => unawaited(_edit(context, null, kind: IptvSourceKind.xtream)),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ],
    );
  }

  static String _refreshIntervalLabel(int days) =>
      days <= 1 ? t.iptv.refreshIntervalDaily : t.iptv.refreshIntervalDays(days: days);

  /// Says what a row is without repeating credentials back at the user.
  String _subtitleFor(IptvSource source) {
    if (!source.isComplete) return t.iptv.incomplete;
    return switch (source.kind) {
      IptvSourceKind.m3u => source.epgUrls.isNotEmpty ? t.iptv.playlistWithGuide : t.iptv.playlistWithoutGuide,
      IptvSourceKind.xtream => source.baseUrl ?? '',
    };
  }

  Future<void> _edit(BuildContext context, IptvSource? existing, {IptvSourceKind? kind}) async {
    final provider = context.read<IptvSourcesProvider>();
    final result = await Navigator.of(context).push<IptvEditResult>(
      MaterialPageRoute(
        builder: (_) => IptvSourceEditScreen(source: existing, kind: kind ?? existing?.kind ?? IptvSourceKind.m3u),
      ),
    );
    if (result == null) return;
    if (result.deleted) {
      await provider.remove(result.source.id);
      return;
    }
    await provider.save(result.source);
  }
}

/// What the edit screen hands back: the edited source, or a request to delete
/// it.
class IptvEditResult {
  const IptvEditResult(this.source, {this.deleted = false});

  final IptvSource source;
  final bool deleted;
}

/// Add or edit one source. Fields differ per kind: a playlist needs a URL and
/// optionally a guide, a panel needs its address and credentials.
class IptvSourceEditScreen extends StatefulWidget {
  const IptvSourceEditScreen({super.key, this.source, required this.kind});

  final IptvSource? source;
  final IptvSourceKind kind;

  @override
  State<IptvSourceEditScreen> createState() => _IptvSourceEditScreenState();
}

class _IptvSourceEditScreenState extends State<IptvSourceEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _playlistUrl;

  /// One controller per guide URL. Always at least one, so the form shows an
  /// empty field to type into.
  late final List<TextEditingController> _epgUrls;
  late final TextEditingController _baseUrl;
  late final TextEditingController _username;
  late final TextEditingController _password;

  /// Required fields left empty at the last save attempt. A [Form] would do
  /// this, but its [TextFormField] cannot be a [FocusableTextField], and on a
  /// remote a field that traps focus is worse than one that validates itself.
  final Set<TextEditingController> _emptyRequired = {};

  /// Xtream only: which container the panel is asked for.
  late IptvStreamFormat _streamFormat;
  late IptvCatchupMode _catchupMode;
  late final TextEditingController _catchupDays;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    _name = TextEditingController(text: source?.name ?? '');
    _playlistUrl = TextEditingController(text: source?.playlistUrl ?? '');
    final storedGuides = source?.epgUrls ?? const <String>[];
    _epgUrls = [
      if (storedGuides.isEmpty)
        TextEditingController()
      else
        for (final url in storedGuides) TextEditingController(text: url),
    ];
    _streamFormat = source?.streamFormat ?? IptvStreamFormat.mpegTs;
    _catchupMode = source?.catchupMode ?? IptvCatchupMode.automatic;
    _catchupDays = TextEditingController(text: source?.catchupDays?.toString() ?? '');
    _baseUrl = TextEditingController(text: source?.baseUrl ?? '');
    _username = TextEditingController(text: source?.username ?? '');
    _password = TextEditingController(text: source?.password ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _playlistUrl.dispose();
    for (final controller in _epgUrls) {
      controller.dispose();
    }
    _baseUrl.dispose();
    _username.dispose();
    _password.dispose();
    _catchupDays.dispose();
    super.dispose();
  }

  bool get _isXtream => widget.kind == IptvSourceKind.xtream;

  /// Which on-screen keyboard the fields raise.
  ///
  /// Read on every build so a change in settings applies without reopening the
  /// form. Paired everywhere with [TvTextInputAutoOpenBehavior.never]: a
  /// keyboard that opens by itself when focus arrives makes the form
  /// untraversable, so it waits for the select button.
  bool get _usesSystemKeyboard => SettingsService.instance.read(SettingsService.useSystemTvKeyboard);

  TvTextInputPresentation get _keyboard =>
      _usesSystemKeyboard ? TvTextInputPresentation.platform : TvTextInputPresentation.flutterOverlay;

  /// Neither keyboard opens by itself. Android TV's docked IME used to come
  /// up on every focus entry, which turns walking the form with a remote into
  /// a fight with the keyboard; the field stays read-only until the select
  /// button asks for it, and then raises whichever keyboard is configured.
  TvTextInputAutoOpenBehavior get _autoOpen => TvTextInputAutoOpenBehavior.never;

  /// Fields that must be filled in, which depends on the kind being edited.
  List<TextEditingController> get _requiredFields => [
    _name,
    if (_isXtream) ...[_baseUrl, _username, _password] else _playlistUrl,
  ];

  void _save() {
    String text(TextEditingController c) => c.text.trim();

    final empty = _requiredFields.where((field) => text(field).isEmpty).toSet();
    if (empty.isNotEmpty) {
      setState(() {
        _emptyRequired
          ..clear()
          ..addAll(empty);
      });
      return;
    }

    final source = IptvSource(
      id: widget.source?.id ?? const Uuid().v4(),
      name: text(_name),
      kind: widget.kind,
      playlistUrl: _isXtream ? null : text(_playlistUrl),
      epgUrls: [
        for (final controller in _epgUrls)
          if (text(controller).isNotEmpty) text(controller),
      ],
      baseUrl: _isXtream ? text(_baseUrl) : null,
      username: _isXtream ? text(_username) : null,
      password: _isXtream ? text(_password) : null,
      streamFormat: _streamFormat,
      catchupMode: _catchupMode,
      catchupDays: int.tryParse(text(_catchupDays)),
    );
    Navigator.of(context).pop(IptvEditResult(source));
  }

  static String _streamFormatLabel(IptvStreamFormat format) =>
      format == IptvStreamFormat.hls ? t.iptv.streamFormatHls : t.iptv.streamFormatMpegTs;

  Future<void> _pickStreamFormat(BuildContext context) async {
    final picked = await showSelectionDialog<IptvStreamFormat>(
      context: context,
      title: t.iptv.streamFormatLabel,
      currentValue: _streamFormat,
      options: [
        for (final format in IptvStreamFormat.values) DialogOption(value: format, title: _streamFormatLabel(format)),
      ],
    );
    if (picked != null && mounted) setState(() => _streamFormat = picked.value);
  }

  static String _catchupModeLabel(IptvCatchupMode mode) => switch (mode) {
    IptvCatchupMode.automatic => t.iptv.catchupAutomatic,
    IptvCatchupMode.off => t.iptv.catchupOff,
    IptvCatchupMode.xtream => t.iptv.catchupXtream,
    IptvCatchupMode.query => t.iptv.catchupQuery,
    IptvCatchupMode.append => t.iptv.catchupAppend,
    IptvCatchupMode.flussonic => t.iptv.catchupFlussonic,
  };

  Future<void> _pickCatchupMode(BuildContext context) async {
    final picked = await showSelectionDialog<IptvCatchupMode>(
      context: context,
      title: t.iptv.catchupLabel,
      currentValue: _catchupMode,
      options: [for (final mode in IptvCatchupMode.values) DialogOption(value: mode, title: _catchupModeLabel(mode))],
    );
    if (picked != null && mounted) setState(() => _catchupMode = picked.value);
  }

  /// The archive rows, offered for both kinds: a panel reports its window per
  /// channel and a playlist declares it per entry, but plenty of providers do
  /// neither and still serve one.
  List<Widget> _buildCatchupFields(BuildContext context) => [
    FocusableListTile(
      leading: const AppIcon(Symbols.history_rounded, fill: 1),
      title: Text(t.iptv.catchupLabel),
      subtitle: Text(_catchupModeLabel(_catchupMode)),
      trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
      onTap: () => unawaited(_pickCatchupMode(context)),
    ),
    Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Text(
        t.iptv.catchupDescription,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
      ),
    ),
    if (_catchupMode != IptvCatchupMode.off)
      FocusableTextField(
        controller: _catchupDays,
        tvTextInputPresentation: _keyboard,
        tvTextInputAutoOpenBehavior: _autoOpen,
        decoration: InputDecoration(
          labelText: t.iptv.catchupDaysLabel,
          hintText: '$kDefaultIptvCatchupDays',
          helperText: t.iptv.catchupDaysDescription,
          helperMaxLines: 3,
        ),
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
      ),
  ];

  String? _errorFor(TextEditingController field) => _emptyRequired.contains(field) ? t.iptv.fieldRequired : null;

  /// Typing answers the complaint, so the complaint goes away.
  void _clearError(TextEditingController field) {
    if (_emptyRequired.remove(field)) setState(() {});
  }

  /// The guide URLs, each removable, with a button to add another. Offered
  /// for both kinds: a panel's own guide is often patchy, and an extra XMLTV
  /// list fills it in.
  List<Widget> _buildGuideFields() => [
    for (var i = 0; i < _epgUrls.length; i++) ...[
      if (i > 0) const SizedBox(height: 8),
      Row(
        crossAxisAlignment: .start,
        children: [
          Expanded(
            child: FocusableTextField(
              controller: _epgUrls[i],
              tvTextInputPresentation: _keyboard,
              tvTextInputAutoOpenBehavior: _autoOpen,
              decoration: InputDecoration(
                labelText: _epgUrls.length == 1 ? t.iptv.guideLabel : t.iptv.guideLabelNumbered(number: i + 1),
                helperText: i == _epgUrls.length - 1 ? t.iptv.guideHelper : null,
                hintText: 'http://provider/epg.xml',
              ),
              keyboardType: TextInputType.url,
            ),
          ),
          if (_epgUrls.length > 1)
            IconButton(
              icon: const AppIcon(Symbols.close_rounded, fill: 1),
              tooltip: t.iptv.removeGuide,
              onPressed: () => setState(() => _epgUrls.removeAt(i).dispose()),
            ),
        ],
      ),
    ],
    const SizedBox(height: 8),
    Align(
      alignment: .centerLeft,
      child: TextButton.icon(
        icon: const AppIcon(Symbols.add_rounded, fill: 1),
        label: Text(t.iptv.addGuide),
        onPressed: () => setState(() => _epgUrls.add(TextEditingController())),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final existing = widget.source;

    return FocusedScrollScaffold(
      title: Text(existing == null ? t.iptv.addTitle : t.iptv.editTitle),
      slivers: [
        SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: .stretch,
                children: [
                  FocusableTextField(
                    controller: _name,
                    tvTextInputPresentation: _keyboard,
                    tvTextInputAutoOpenBehavior: _autoOpen,
                    decoration: InputDecoration(labelText: t.iptv.nameLabel, errorText: _errorFor(_name)),
                    onChanged: (_) => _clearError(_name),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  if (_isXtream) ...[
                    FocusableTextField(
                      controller: _baseUrl,
                      tvTextInputPresentation: _keyboard,
                      tvTextInputAutoOpenBehavior: _autoOpen,
                      decoration: InputDecoration(
                        labelText: t.iptv.serverLabel,
                        hintText: 'http://panel:8080',
                        errorText: _errorFor(_baseUrl),
                      ),
                      onChanged: (_) => _clearError(_baseUrl),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    FocusableTextField(
                      controller: _username,
                      tvTextInputPresentation: _keyboard,
                      tvTextInputAutoOpenBehavior: _autoOpen,
                      decoration: InputDecoration(labelText: t.iptv.usernameLabel, errorText: _errorFor(_username)),
                      onChanged: (_) => _clearError(_username),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    FocusableTextField(
                      controller: _password,
                      tvTextInputPresentation: _keyboard,
                      tvTextInputAutoOpenBehavior: _autoOpen,
                      decoration: InputDecoration(labelText: t.iptv.passwordLabel, errorText: _errorFor(_password)),
                      onChanged: (_) => _clearError(_password),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    // A row that opens a chooser, not a radio group: Flutter
                    // walks a group of radios with the arrow keys, so on a
                    // remote the pair swallowed every DOWN and the fields
                    // below it could not be reached at all.
                    FocusableListTile(
                      leading: const AppIcon(Symbols.tune_rounded, fill: 1),
                      title: Text(t.iptv.streamFormatLabel),
                      subtitle: Text(_streamFormatLabel(_streamFormat)),
                      trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
                      onTap: () => unawaited(_pickStreamFormat(context)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                      child: Text(
                        t.iptv.streamFormatDescription,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ] else ...[
                    FocusableTextField(
                      controller: _playlistUrl,
                      tvTextInputPresentation: _keyboard,
                      tvTextInputAutoOpenBehavior: _autoOpen,
                      decoration: InputDecoration(
                        labelText: t.iptv.playlistLabel,
                        hintText: 'http://provider/list.m3u',
                        errorText: _errorFor(_playlistUrl),
                      ),
                      onChanged: (_) => _clearError(_playlistUrl),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                    ),
                  ],
                  const SizedBox(height: 16),
                  ..._buildGuideFields(),
                  const SizedBox(height: 16),
                  ..._buildCatchupFields(context),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _save, child: Text(t.common.save)),
                  if (existing != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(IptvEditResult(existing, deleted: true)),
                      child: Text(t.iptv.removeSource),
                    ),
                  ],
                ],
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
