import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/providers/companion_remote_provider.dart';
import 'package:plezy/services/companion_remote/remote_pairing_handshake.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/companion_remote/pairing_code_prompt.dart';
import 'package:provider/provider.dart';

class _PromptingProvider extends CompanionRemoteProvider {
  RemotePairingPrompt? _prompt;
  int declined = 0;

  set prompt(RemotePairingPrompt? value) {
    _prompt = value;
    notifyListeners();
  }

  @override
  RemotePairingPrompt? get pairingPrompt => _prompt;

  @override
  void cancelPairing() => declined++;
}

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  Future<_PromptingProvider> pump(WidgetTester tester) async {
    final provider = _PromptingProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<CompanionRemoteProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: const CompanionRemotePairingPrompt(child: Scaffold(body: Text('home'))),
        ),
      ),
    );
    return provider;
  }

  RemotePairingPrompt prompt(String code) => RemotePairingPrompt(
    code: code,
    deviceName: 'Handy',
    platform: 'android',
    expiresAt: DateTime.now().add(RemotePairingHandshake.codeLifetime),
  );

  testWidgets('the code shows over the app while a phone pairs, and goes when the run ends', (tester) async {
    final provider = await pump(tester);
    expect(find.byType(AlertDialog), findsNothing);

    provider.prompt = prompt('12345678');
    await tester.pumpAndSettle();
    expect(find.text('1234 5678'), findsOneWidget);
    expect(find.text(t.companionRemote.pairing.codeMessage(name: 'Handy')), findsOneWidget);

    provider.prompt = null;
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a new run replaces the code on screen', (tester) async {
    final provider = await pump(tester);
    provider.prompt = prompt('12345678');
    await tester.pumpAndSettle();
    provider.prompt = prompt('87654321');
    await tester.pumpAndSettle();
    expect(find.text('1234 5678'), findsNothing);
    expect(find.text('8765 4321'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('cancel and back both decline the pairing', (tester) async {
    final provider = await pump(tester);
    provider.prompt = prompt('12345678');
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.common.cancel));
    await tester.pump();
    expect(provider.declined, 1);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(provider.declined, 2, reason: 'back on a remote declines rather than hiding the code');
  });
}
