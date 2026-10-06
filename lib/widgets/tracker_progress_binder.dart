import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../media/ids.dart';
import '../profiles/active_profile_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/trackers_provider.dart';
import '../services/settings_service.dart';
import '../services/watch_progress/external_id_index_client.dart';
import '../services/watch_progress/tracker_progress_controller.dart';

/// Tells [TrackerProgressController] who is watching (fork addition): the
/// active profile, whether it keeps its progress in Simkl, its Simkl session,
/// and the servers online. Binds again whenever one of them changes; a
/// profile on the server's progress costs one comparison per rebuild.
class TrackerProgressBinder extends StatefulWidget {
  const TrackerProgressBinder({super.key, required this.child});

  final Widget child;

  @override
  State<TrackerProgressBinder> createState() => _TrackerProgressBinderState();
}

class _TrackerProgressBinderState extends State<TrackerProgressBinder> {
  String? _bound;
  Listenable? _choice;

  @override
  void initState() {
    super.initState();
    final settings = SettingsService.instanceOrNull;
    _choice = settings?.listenable(SettingsService.simklLedProfiles);
    _choice?.addListener(_onChoice);
  }

  @override
  void dispose() {
    _choice?.removeListener(_onChoice);
    super.dispose();
  }

  void _onChoice() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final profileId = context.watch<ActiveProfileProvider?>()?.activeId;
    final simkl = context.watch<TrackersProvider?>()?.simklCatalogClient;
    final multiServer = context.watch<MultiServerProvider?>();
    final led = SettingsService.instanceOrNull?.read(SettingsService.simklLedProfiles) ?? const [];
    final trackerLed = profileId != null && led.contains(profileId);

    final servers = <String, ExternalIdIndexClient>{};
    if (trackerLed && multiServer != null) {
      for (final id in multiServer.onlineServerIds) {
        final client = multiServer.getClientForServer(ServerId(id));
        if (client != null && client is ExternalIdIndexClient) {
          servers[client.serverId] = client as ExternalIdIndexClient;
        }
      }
    }
    final signature = [profileId, trackerLed, identityHashCode(simkl), ...(servers.keys.toList()..sort())].join('|');
    if (signature != _bound) {
      _bound = signature;
      unawaited(
        TrackerProgressController.instance.bind(
          profileId: profileId,
          trackerLed: trackerLed,
          simkl: simkl,
          servers: servers,
        ),
      );
    }
    return widget.child;
  }
}
