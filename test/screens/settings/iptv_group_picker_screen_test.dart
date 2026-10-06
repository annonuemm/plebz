import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/iptv_group_picker_screen.dart';
import 'package:plezy/services/iptv/iptv_live_tv_source.dart';
import 'package:plezy/theme/mono_theme.dart';

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  const options = [
    IptvGroupOption(key: 'DE • Sport', label: 'DE • Sport', channelCount: 40),
    IptvGroupOption(key: 'UK • News', label: 'UK • News', channelCount: 12),
    IptvGroupOption(key: 'US • Movies', label: 'US • Movies', channelCount: 300),
  ];

  Future<List<String>? Function()> open(
    WidgetTester tester, {
    List<String>? selected,
    List<String> known = const [],
  }) async {
    List<String>? result;
    var closed = false;
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(
                  context,
                ).push(IptvGroupPickerScreen.route(options: options, selected: selected, known: known));
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => closed ? result : throw StateError('still open');
  }

  testWidgets('a source that never chose starts with every group ticked', (tester) async {
    await open(tester);
    expect(find.text(t.iptv.groupsChosenWithChannels(chosen: 3, total: 3, channels: 352)), findsOneWidget);
  });

  testWidgets('none, then two, are applied in the provider\'s order', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text(t.iptv.groupsNone));
    await tester.pump();
    await tester.tap(find.text('US • Movies'));
    await tester.tap(find.text('DE • Sport'));
    await tester.pump();
    expect(find.text(t.iptv.groupsChosenWithChannels(chosen: 2, total: 3, channels: 340)), findsOneWidget);

    await tester.tap(find.text(t.iptv.groupsApply));
    await tester.pumpAndSettle();
    expect(result(), ['DE • Sport', 'US • Movies']);
  });

  testWidgets('a group the provider added since is marked new and left unticked', (tester) async {
    await open(tester, selected: ['DE • Sport'], known: ['DE • Sport', 'UK • News']);
    expect(find.text('${t.iptv.groupsChannelCount(count: 300)} · ${t.iptv.groupsNew}'), findsOneWidget);
    expect(find.text(t.iptv.groupsChannelCount(count: 12)), findsOneWidget, reason: 'known, so not new');
    expect(find.text(t.iptv.groupsChosenWithChannels(chosen: 1, total: 3, channels: 40)), findsOneWidget);
  });

  testWidgets('leaving without applying changes nothing', (tester) async {
    final result = await open(tester, selected: ['UK • News']);
    await tester.tap(find.text(t.iptv.groupsAll));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(result(), isNull);
  });
}
