import 'dart:async';

import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../models/livetv_channel.dart';
import '../navigation/main_screen_scope.dart';
import '../navigation/navigation_tabs.dart';
import '../providers/multi_server_provider.dart';
import '../screens/sport/sport_broadcast_finder.dart';
import '../services/live_tv_last_selection.dart';
import '../services/program_reminder_notifications.dart';
import '../services/program_reminders.dart';
import '../utils/formatters.dart';
import '../utils/live_tv_matching.dart';
import '../utils/live_tv_player_navigation.dart';
import '../utils/notification_permission.dart';
import '../utils/snackbar_helper.dart';
import 'dialog_action_button.dart';

/// Brings up a reminder set in the guide when its programme is about to start
/// (fork addition), on top of whatever is on screen — the player included —
/// with the channel one press away.
///
/// A timer waits for the next one only; it is set again whenever the
/// reminders change. A reminder that has been shown is gone.
///
/// Plebz: on a phone or tablet the reminders also go to Android as
/// notifications ([ProgramReminderNotifications]), which come when the app is
/// closed. Away from the screen the app shows nothing itself — a window
/// opened behind the viewer's back used to take the reminder with it unseen —
/// and on coming back it drops what Android has already shown and switches
/// over to a reminder whose notification was tapped.
class ProgramReminderHost extends StatefulWidget {
  const ProgramReminderHost({super.key, required this.child});

  final Widget child;

  /// How long an unanswered reminder stays up.
  static const Duration showFor = Duration(minutes: 2);

  @override
  State<ProgramReminderHost> createState() => _ProgramReminderHostState();
}

class _ProgramReminderHostState extends State<ProgramReminderHost> with WidgetsBindingObserver {
  final ProgramReminders _reminders = ProgramReminders.instance;
  final ProgramReminderNotifications _notifications = ProgramReminderNotifications.instance;
  Timer? _timer;
  Route<void>? _shown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reminders.addListener(_onRemindersChanged);
    _notifications.listen(() => unawaited(_catchUp()));
    if (_reminders.isLoaded) {
      _onRemindersChanged();
      unawaited(_catchUp());
    } else {
      unawaited(
        _reminders.ensureLoaded().then((_) {
          _onRemindersChanged();
          return _catchUp();
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifications.stopListening();
    _reminders.removeListener(_onRemindersChanged);
    _timer?.cancel();
    final shown = _shown;
    if (shown != null && shown.isActive) shown.navigator?.removeRoute(shown);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_catchUp());
  }

  /// Whether the viewer can see a window opened now. Not merely inactive: a
  /// desktop window that lost focus is still on screen.
  bool get _onScreen {
    final state = WidgetsBinding.instance.lifecycleState;
    return state != AppLifecycleState.hidden && state != AppLifecycleState.paused;
  }

  void _onRemindersChanged() {
    _schedule();
    // Once initState is through — the notification's words read the context's
    // clock format — but not after a frame: none is drawn in the background.
    scheduleMicrotask(_syncNotifications);
  }

  void _syncNotifications() {
    if (!mounted || !_notifications.supported) return;
    final is24Hour = MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false;
    final notices = [
      for (final reminder in _reminders.entries)
        ProgramReminderNotice(
          id: reminder.key,
          at: reminder.startsAt.subtract(ProgramReminders.lead),
          endsAt: reminder.endsAtTime,
          title: reminder.title,
          text: [
            t.reminders.soonTitle,
            reminder.channelTitle,
            formatClockTime(reminder.startsAt, is24Hour: is24Hour),
          ].where((part) => part.isNotEmpty).join(' · '),
          action: t.reminders.tune,
        ),
    ];
    unawaited(_notifications.replaceAll(notices, channelName: t.reminders.notificationChannel));
    // Android 13 asks once, with the first reminder there is.
    if (notices.isNotEmpty) unawaited(NotificationPermission.ensure());
  }

  /// Back on screen, or opened from a notification: what Android has already
  /// shown is not shown again, a tapped one switches over, and anything still
  /// due comes up now.
  Future<void> _catchUp() async {
    if (_notifications.supported) {
      final opened = await _notifications.takeOpened();
      final fired = await _notifications.takeFired();
      final reminder = opened == null ? null : _reminders.entries.firstWhereOrNull((entry) => entry.key == opened);
      for (final key in {...fired, ?opened}) {
        await _reminders.remove(key);
      }
      if (reminder != null && mounted) await _tune(reminder);
    }
    if (mounted) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!mounted) return;
    final next = _reminders.nextDueAt();
    if (next == null) return;
    final wait = next.difference(clock.now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, _fire);
  }

  void _fire() {
    if (!mounted) return;
    // One at a time; the next waits for this one to be answered.
    if (_shown != null) return;
    // Nobody to see it: kept for the return (see [_catchUp]).
    if (!_onScreen) return;
    final reminder = _reminders.due().firstOrNull;
    if (reminder == null) {
      _schedule();
      return;
    }
    unawaited(_reminders.remove(reminder.key));
    _show(reminder);
  }

  void _show(ProgramReminder reminder) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: true,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (dialogContext) => _ReminderDialog(
        reminder: reminder,
        onClose: () => Navigator.of(dialogContext).pop(),
        onTune: () {
          Navigator.of(dialogContext).pop();
          unawaited(_tune(reminder));
        },
      ),
    );
    _shown = route;
    final expiry = Timer(ProgramReminderHost.showFor, () {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
    navigator.push(route).whenComplete(() {
      expiry.cancel();
      if (identical(_shown, route)) _shown = null;
      // Another may have come due while this one was up.
      if (mounted) _schedule();
    });
  }

  Future<void> _tune(ProgramReminder reminder) => tuneProgramReminder(context, reminder);

  @override
  Widget build(BuildContext context) => widget.child;
}

/// To the reminder's channel, the way the home screen's live row goes there:
/// the guide handed the channel, the player opened over it. Also what the
/// screensaver's reminder scene asks for (`plebz://reminder`), where the main
/// screen passes its own [showLiveTvTab].
Future<void> tuneProgramReminder(BuildContext context, ProgramReminder reminder, {VoidCallback? showLiveTvTab}) async {
  final multiServer = context.read<MultiServerProvider?>();
  final finder = SportBroadcastFinder.maybeOf(context);
  if (multiServer == null || finder == null) return;
  final channels = await finder.channels();
  if (!context.mounted) return;
  final channel = channels.firstWhereOrNull((c) => liveTvChannelScopeKey(c) == reminder.channelScopeKey);
  if (channel == null) {
    showErrorSnackBar(context, t.reminders.channelGone(channel: reminder.channelTitle));
    return;
  }
  LiveTvLastSelection.instance.handOff(
    channelKey: liveTvChannelScopeKey(channel),
    group: liveTvNonEmpty(channel.lineup),
  );
  if (showLiveTvTab != null) {
    showLiveTvTab();
  } else {
    MainScreenTabSwitcher.selectTabOf(context, NavigationTabId.liveTv);
  }
  await navigateToLiveTv(
    context,
    multiServer: multiServer,
    channel: channel,
    channels: channels,
    group: liveTvNonEmpty(channel.lineup),
  );
}

class _ReminderDialog extends StatelessWidget {
  const _ReminderDialog({required this.reminder, required this.onClose, required this.onTune});

  final ProgramReminder reminder;
  final VoidCallback onClose;
  final VoidCallback onTune;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final started = !reminder.startsAt.isAfter(clock.now());
    final time = formatClockTime(reminder.startsAt, is24Hour: MediaQuery.alwaysUse24HourFormatOf(context));
    return AlertDialog(
      title: Text(started ? t.reminders.runningTitle : t.reminders.soonTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reminder.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('${reminder.channelTitle} · $time', style: theme.textTheme.bodyMedium),
        ],
      ),
      actions: [
        DialogActionButton(onPressed: onClose, label: t.common.close),
        DialogActionButton(autofocus: true, isPrimary: true, onPressed: onTune, label: t.reminders.tune),
      ],
    );
  }
}
