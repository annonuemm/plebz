import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../services/settings_service.dart';
import '../../services/tmdb/tmdb_fill_in_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/dialog_action_button.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';

/// Settings for the TMDB artwork fill-in: the switch, the user's own API key,
/// and the two maintenance actions that are otherwise impossible to trigger
/// (checking the key, and forgetting what has been looked up so far).
class TmdbSettingsScreen extends StatefulWidget {
  const TmdbSettingsScreen({super.key});

  @override
  State<TmdbSettingsScreen> createState() => _TmdbSettingsScreenState();
}

class _TmdbSettingsScreenState extends State<TmdbSettingsScreen> {
  bool _isVerifying = false;

  bool get _hasKey => (SettingsService.instance.read(SettingsService.tmdbApiKey) ?? '').trim().isNotEmpty;

  Future<void> _editKey() async {
    final saved = await showDialog<bool>(context: context, builder: (_) => const _TmdbKeyDialog());
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _verify() async {
    final service = TmdbFillInService.instanceOrNull;
    if (service == null || _isVerifying) return;

    setState(() => _isVerifying = true);
    final valid = await service.verifyCredential();
    if (!mounted) return;
    setState(() => _isVerifying = false);
    if (valid) {
      showSuccessSnackBar(context, t.services.tmdb.verifyValid);
    } else {
      showErrorSnackBar(context, t.services.tmdb.verifyInvalid);
    }
  }

  Future<void> _clearCache() async {
    final service = TmdbFillInService.instanceOrNull;
    if (service == null) return;
    await service.clearCache();
    if (mounted) showSuccessSnackBar(context, t.services.tmdb.cacheCleared);
  }

  @override
  Widget build(BuildContext context) {
    // The switch stays usable without a key so the two can be set in either
    // order; until both are in place the service simply answers "no logo".
    final hasKey = _hasKey;
    return SettingsPage(
      title: Text(t.services.tmdb.title),
      children: [
        SettingsGroup(
          children: [
            SettingSwitchTile(
              pref: SettingsService.tmdbLogosEnabled,
              icon: Symbols.imagesmode_rounded,
              title: t.services.tmdb.enabled,
              subtitle: t.services.tmdb.enabledDescription,
            ),
            FocusableListTile(
              leading: const AppIcon(Symbols.key_rounded, fill: 1),
              title: Text(t.services.tmdb.apiKey),
              subtitle: Text(hasKey ? t.services.tmdb.apiKeySet : t.services.tmdb.apiKeyHelp),
              trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
              onTap: _editKey,
            ),
            FocusableListTile(
              leading: const AppIcon(Symbols.check_circle_rounded, fill: 1),
              title: Text(t.services.tmdb.verify),
              subtitle: hasKey ? null : Text(t.services.tmdb.apiKeyMissing),
              trailing: _isVerifying
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              enabled: hasKey && !_isVerifying,
              onTap: _verify,
            ),
            FocusableListTile(
              leading: const AppIcon(Symbols.delete_sweep_rounded, fill: 1),
              title: Text(t.services.tmdb.clearCache),
              subtitle: Text(t.services.tmdb.clearCacheDescription),
              onTap: _clearCache,
            ),
          ],
        ),
      ],
    );
  }
}

/// Key entry. A dialog rather than an inline field because entering one on a
/// TV means a remote and an on-screen keyboard, which needs the whole screen.
class _TmdbKeyDialog extends StatefulWidget {
  const _TmdbKeyDialog();

  @override
  State<_TmdbKeyDialog> createState() => _TmdbKeyDialogState();
}

class _TmdbKeyDialogState extends State<_TmdbKeyDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: SettingsService.instance.read(SettingsService.tmdbApiKey) ?? '',
  );
  final _saveFocusNode = FocusNode(debugLabel: 'TmdbKeySave');

  @override
  void dispose() {
    _saveFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    await SettingsService.instance.write(SettingsService.tmdbApiKey, value.isEmpty ? null : value);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.services.tmdb.apiKey),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FocusableTextField(
            controller: _controller,
            decoration: InputDecoration(labelText: t.services.tmdb.apiKeyHint),
            autofocus: true,
            textInputAction: TextInputAction.done,
            onEditingComplete: () => _saveFocusNode.requestFocus(),
            onNavigateDown: _saveFocusNode.requestFocus,
          ),
          const SizedBox(height: 12),
          Text(t.services.tmdb.apiKeyHelp, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        DialogActionButton(onPressed: () => Navigator.pop(context), label: t.common.cancel),
        DialogActionButton(focusNode: _saveFocusNode, onPressed: _save, label: t.common.save),
      ],
    );
  }
}
