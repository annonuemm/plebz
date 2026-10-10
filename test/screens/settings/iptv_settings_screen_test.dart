import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/providers/iptv_sources_provider.dart';
import 'package:plezy/screens/settings/iptv_settings_screen.dart';
import 'package:plezy/services/iptv/iptv_source.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';

import 'package:plezy/widgets/focusable_list_tile.dart';

import '../../test_helpers/prefs.dart';

/// The add/edit form is the only way into IPTV, and on TV it is filled in with
/// a remote. Plain text fields hand that job to the box's own on-screen
/// keyboard, which is exactly what left the form unfillable on one; every
/// field here therefore raises Plebz's own keyboard, the way the Jellyfin
/// connection form already does.
const _xtreamExisting = IptvSource(
  id: 'x',
  name: 'Mein Panel',
  kind: IptvSourceKind.xtream,
  baseUrl: 'http://panel:8080',
  username: 'u',
  password: 'p',
);

const _existing = IptvSource(
  id: 'a',
  name: 'Meine Liste',
  kind: IptvSourceKind.m3u,
  playlistUrl: 'http://provider/list.m3u',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> pumpEditor(WidgetTester tester, {IptvSource? source, IptvSourceKind kind = IptvSourceKind.m3u}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: IptvSourceEditScreen(source: source, kind: kind),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("focus alone leaves Plebz's keyboard closed", (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.useSystemTvKeyboard, false);

    await pumpEditor(tester, source: _existing);

    tester.widgetList<EditableText>(find.byType(EditableText)).first.focusNode.requestFocus();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('tv_virtual_keyboard_dialog')),
      findsNothing,
      reason: 'a keyboard that opens on arrival makes the form impossible to walk through',
    );
  });

  testWidgets("the device's keyboard is left in charge by default", (tester) async {
    await pumpEditor(tester, source: _existing);

    tester.widgetList<EditableText>(find.byType(EditableText)).first.focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('tv_virtual_keyboard_dialog')),
      findsNothing,
      reason: "the device raises its own keyboard; Plebz must not put one on top of it",
    );
  });

  testWidgets("Plebz's own keyboard takes over when the setting says so", (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.useSystemTvKeyboard, false);

    await pumpEditor(tester, source: _existing);

    tester.widgetList<EditableText>(find.byType(EditableText)).first.focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tv_virtual_keyboard_dialog')), findsOneWidget);
  });

  testWidgets("the device's keyboard waits for select on Android TV", (tester) async {
    // Android TV's IME is docked rather than modal, so the shared default is
    // to raise it as soon as a field takes focus. In a form that means the
    // keyboard reappears on every step through the fields; here it stays down
    // until the select button asks for it.
    TvDetectionService.debugSetAppleTVOverride(null);
    await TvDetectionService.getInstance(forceTv: true);
    TvDetectionService.setForceTVSync(true);
    addTearDown(() => TvDetectionService.setForceTVSync(false));

    await pumpEditor(tester, source: _existing);

    bool firstFieldIsReadOnly() => tester.widgetList<TextField>(find.byType(TextField)).first.readOnly;

    tester.widgetList<EditableText>(find.byType(EditableText)).first.focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(firstFieldIsReadOnly(), isTrue, reason: 'arriving at a field must not raise the box keyboard');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(firstFieldIsReadOnly(), isFalse, reason: 'select is what asks for the keyboard');
  });

  testWidgets('the stream format does not trap the D-pad above the guide fields', (tester) async {
    // Flutter walks a group of radio buttons with the arrow keys. In a form
    // that means DOWN never leaves the pair: the guide fields below could not
    // be reached with a remote at all.
    await pumpEditor(tester, source: _xtreamExisting, kind: IptvSourceKind.xtream);

    final formatTile = find.widgetWithText(FocusableListTile, t.iptv.streamFormatLabel);
    expect(formatTile, findsOneWidget);

    // Both choices live behind the row rather than beside it, so there is no
    // second stop to get caught between: the row names the format in force,
    // and the alternative is only reachable by opening it. (Upstream 2.20
    // retired FocusableRadioListTile, which this used to name as the widget
    // to stay away from; the absent alternative is the assertion now.)
    expect(find.text(t.iptv.streamFormatHls), findsNothing);
  });

  testWidgets('the archive form can be picked for either kind of source', (tester) async {
    // The user runs Xtream, but a playlist addresses its archive differently
    // and the app cannot always tell which — so the form is a choice, on both.
    await pumpEditor(tester, source: _existing);

    expect(find.text(t.iptv.catchupLabel), findsOneWidget);
    expect(find.text(t.iptv.catchupAutomatic), findsOneWidget);

    await tester.tap(find.widgetWithText(FocusableListTile, t.iptv.catchupLabel));
    await tester.pumpAndSettle();

    for (final label in [
      t.iptv.catchupOff,
      t.iptv.catchupXtream,
      t.iptv.catchupQuery,
      t.iptv.catchupAppend,
      t.iptv.catchupFlussonic,
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label must be offered');
    }

    await tester.tap(find.text(t.iptv.catchupFlussonic));
    await tester.pumpAndSettle();

    expect(find.text(t.iptv.catchupFlussonic), findsOneWidget, reason: 'the row now shows the picked form');
  });

  testWidgets('an empty required field is reported and blocks saving', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.text(t.common.save));
    await tester.pumpAndSettle();

    // Two required fields on an M3U source, and the screen stays put.
    expect(find.text(t.iptv.fieldRequired), findsNWidgets(2));
    expect(find.byType(IptvSourceEditScreen), findsOneWidget);
  });

  testWidgets('typing answers the complaint', (tester) async {
    // Off the TV path on purpose: there the field is driven by the system's
    // own keyboard host, which a widget test cannot type into.
    TvDetectionService.debugSetAppleTVOverride(false);
    await pumpEditor(tester);

    await tester.tap(find.text(t.common.save));
    await tester.pumpAndSettle();
    expect(find.text(t.iptv.fieldRequired), findsNWidgets(2));

    await tester.enterText(find.byType(EditableText).first, 'Meine Liste');
    await tester.pumpAndSettle();

    expect(find.text(t.iptv.fieldRequired), findsOneWidget);
  });

  testWidgets("Live TV's own settings sit on the IPTV page", (tester) async {
    tester.view.physicalSize = const Size(1920, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = IptvSourcesProvider(profileId: 'p', buildSource: (_) => throw UnimplementedError());
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<IptvSourcesProvider>.value(
          value: provider,
          child: MaterialApp(theme: monoTheme(dark: true), home: const IptvSettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.settings.liveTv), findsOneWidget);
    expect(find.text(t.settings.liveTvDefaultFavorites), findsOneWidget);
    final before = SettingsService.instance.read(SettingsService.liveTvGuideTimeNavigation);
    await tester.tap(find.text(t.settings.liveTvGuideTimeNavigation));
    await tester.pumpAndSettle();
    expect(SettingsService.instance.read(SettingsService.liveTvGuideTimeNavigation), !before);
  });
}
