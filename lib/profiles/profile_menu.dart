import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../screens/profile/profile_switch_screen.dart';
import '../screens/profile/profile_teardown.dart';
import '../utils/dialogs.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_menu.dart';
import 'active_profile_provider.dart';
import 'profile_activation.dart';
import 'profile_avatar.dart';

/// The profile menu: the other profiles to switch to, managing them, the
/// settings, signing out (Plebz).
///
/// One menu for the two places that open it — the start page's header, and
/// under "Flach" the profile row at the foot of the navigation — so they offer
/// the same and do the same.
abstract final class ProfileMenu {
  /// Whether a switch begun from this menu is under way. The start page covers
  /// itself while it is, wherever the switch was started from.
  static final ValueNotifier<bool> switching = ValueNotifier(false);

  static List<AppMenuEntry<String>> entries(BuildContext context) {
    final activeProvider = context.read<ActiveProfileProvider>();
    final active = activeProvider.active;
    final theme = Theme.of(context);
    final switchable = activeProvider.profiles.where((p) => p.id != active?.id).toList();

    return [
      for (final p in switchable)
        AppMenuItem<String>(
          value: 'profile:${p.id}',
          leading: ProfileAvatar(profile: p, size: 24, avatarUrl: activeProvider.avatarUrlFor(p.id)),
          label: p.displayName,
          trailing: p.isPinProtected
              ? AppIcon(Symbols.lock_rounded, fill: 1, size: 14, color: theme.colorScheme.onSurfaceVariant)
              : null,
        ),
      if (switchable.isNotEmpty) const AppMenuDivider(),
      AppMenuItem<String>(value: 'manage_profiles', icon: Symbols.group_rounded, label: t.profiles.sectionTitle),
      AppMenuItem<String>(value: 'settings', icon: Symbols.settings_rounded, label: t.common.settings),
      AppMenuItem<String>(value: 'logout', icon: Symbols.logout_rounded, label: t.common.logout),
    ];
  }

  /// Does what [value], one of [entries]' values, asks for. [openSettings] is
  /// the caller's own way to the settings.
  static Future<void> handle(BuildContext context, String value, {required VoidCallback openSettings}) async {
    if (switching.value) return;
    switch (value) {
      case 'logout':
        unawaited(_logout(context));
      case 'manage_profiles':
        Navigator.of(
          context,
          rootNavigator: true,
        ).push(MaterialPageRoute(builder: (context) => const ProfileSwitchScreen()));
      case 'settings':
        openSettings();
      default:
        if (!value.startsWith('profile:')) return;
        final id = value.substring('profile:'.length);
        final target = context.read<ActiveProfileProvider>().profiles.where((p) => p.id == id).firstOrNull;
        if (target == null) return;
        switching.value = true;
        try {
          await switchProfileFromUi(context, target);
        } finally {
          switching.value = false;
        }
    }
  }

  static Future<void> _logout(BuildContext context) async {
    final confirm = await showConfirmDialog(
      context,
      title: t.common.logout,
      message: t.messages.logoutConfirm,
      confirmText: t.common.logout,
      isDestructive: true,
    );
    if (confirm && context.mounted) await logoutAllProfiles(context);
  }
}
