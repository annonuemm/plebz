import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../providers/companion_remote_provider.dart';
import '../../services/companion_remote/remote_pairing_handshake.dart';
import '../dialog_action_button.dart';

/// Shows the pairing code on the host whenever a phone asks to pair, on top of
/// whatever is on screen — the player included — and takes it away again
/// once the run is over: paired, expired, refused or declined here.
class CompanionRemotePairingPrompt extends StatefulWidget {
  const CompanionRemotePairingPrompt({super.key, required this.child});

  final Widget child;

  @override
  State<CompanionRemotePairingPrompt> createState() => _CompanionRemotePairingPromptState();
}

class _CompanionRemotePairingPromptState extends State<CompanionRemotePairingPrompt> {
  CompanionRemoteProvider? _provider;
  RemotePairingPrompt? _shown;
  Route<void>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<CompanionRemoteProvider?>();
    if (identical(provider, _provider)) return;
    _provider?.removeListener(_onChanged);
    _provider = provider?..addListener(_onChanged);
    _onChanged();
  }

  @override
  void dispose() {
    _provider?.removeListener(_onChanged);
    _close();
    super.dispose();
  }

  void _onChanged() {
    final prompt = _provider?.pairingPrompt;
    if (identical(prompt, _shown)) return;
    _close();
    _shown = prompt;
    if (prompt == null || !mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (_) => _PairingCodeDialog(prompt: prompt, onDecline: () => _provider?.cancelPairing()),
    );
    _route = route;
    navigator.push(route).whenComplete(() {
      if (identical(_route, route)) _route = null;
    });
  }

  void _close() {
    final route = _route;
    _route = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PairingCodeDialog extends StatelessWidget {
  const _PairingCodeDialog({required this.prompt, required this.onDecline});

  final RemotePairingPrompt prompt;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = prompt.deviceName.isEmpty ? t.companionRemote.unknownDevice : prompt.deviceName;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onDecline();
      },
      child: AlertDialog(
        title: Text(t.companionRemote.pairing.codeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.companionRemote.pairing.codeMessage(name: name)),
            const SizedBox(height: 20),
            Center(
              child: Semantics(
                label: prompt.code.split('').join(' '),
                child: ExcludeSemantics(
                  child: Text(
                    RemotePairingHandshake.formatCode(prompt.code),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(t.companionRemote.pairing.codeValidFor, style: theme.textTheme.bodySmall),
          ],
        ),
        actions: [DialogActionButton(autofocus: true, onPressed: onDecline, label: t.common.cancel)],
      ),
    );
  }
}
