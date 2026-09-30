import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/redesign/ocker_guide_panel.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/screens/livetv/guide_preview_player.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/codec_utils.dart';
import 'package:provider/provider.dart';

import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';

/// The guide's band under the redesign: beside the source and the channel it
/// names, what the picture is actually receiving — on capsules of glass, and
/// only while the cursor is on the channel in the picture.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeDateFormatting('en');
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
    GuidePreviewPlayerState.debugSuppressPlayback = true;
  });
  tearDown(() => GuidePreviewPlayerState.debugSuppressPlayback = false);

  final erste = LiveTvChannel(key: 'iptv:erste', callSign: 'Das Erste HD', serverId: 'iptv', serverName: 'Prisma');
  final zdf = LiveTvChannel(key: 'iptv:zdf', callSign: 'ZDF HD', serverId: 'iptv', serverName: 'Prisma');
  final program = LiveTvProgram(title: 'Tagesschau', beginsAt: 1_800_000_000, endsAt: 1_800_000_900);
  final audio = '${CodecUtils.formatAudioCodec('aac')} ${CodecUtils.formatAudioChannels(2)}';

  Future<ValueNotifier<GuideStreamInfo?>> pumpPanel(WidgetTester tester, {required LiveTvChannel focused}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final servers = testMultiServerProvider(MultiServerManager());
    addTearDown(servers.dispose);
    final info = ValueNotifier<GuideStreamInfo?>(null);
    addTearDown(info.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: servers,
        child: MaterialApp(
          theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: OckerGuidePanel(
                previewChannel: erste,
                focusedChannel: focused,
                focusedProgram: program,
                sourceLabel: 'Prisma',
                streamInfo: info,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return info;
  }

  const playing = GuideStreamInfo(
    channelKey: 'iptv:erste',
    width: 1920,
    height: 1080,
    fps: 50,
    audioCodec: 'aac',
    audioChannels: 2,
  );

  testWidgets('on the channel in the picture, its stream stands on glass beside the eyebrow', (tester) async {
    final info = await pumpPanel(tester, focused: erste);
    final titleBefore = tester.getTopLeft(find.text('Tagesschau'));

    info.value = playing;
    await tester.pump();

    for (final label in ['1080p', '50 fps', audio]) {
      expect(
        find.ancestor(of: find.text(label), matching: find.byType(OckerGlassPlate)),
        findsOneWidget,
        reason: label,
      );
    }
    final eyebrow = tester.getRect(find.text('PRISMA · DAS ERSTE HD'));
    final chip = tester.getRect(find.text('1080p'));
    expect(chip.left, greaterThan(eyebrow.right), reason: 'behind the channel');
    expect(chip.center.dy, closeTo(eyebrow.center.dy, 1), reason: 'on its line');
    expect(tester.getTopLeft(find.text('Tagesschau')), titleBefore, reason: 'the title does not move for them');
  });

  testWidgets('on another channel the capsules stay away', (tester) async {
    final info = await pumpPanel(tester, focused: zdf);
    info.value = playing;
    await tester.pump();

    expect(find.text('1080p'), findsNothing);
    expect(find.text('50 fps'), findsNothing);
  });

  test('a whole rate is written whole', () {
    expect(OckerGuidePanel.streamFpsLabel(50), '50 fps');
    expect(OckerGuidePanel.streamFpsLabel(25.001), '25 fps');
    expect(OckerGuidePanel.streamFpsLabel(29.97), '29.97 fps');
  });
}
