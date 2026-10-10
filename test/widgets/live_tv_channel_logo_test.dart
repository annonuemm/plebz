import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/iptv/public_logo_index.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/live_tv_channel_logo.dart';
import 'package:plezy/widgets/optimized_media_image.dart';

import '../test_helpers/io_fakes.dart';
import '../test_helpers/prefs.dart';

/// A channel's logo tries the playlist's, then the guide's, then gives the
/// name — and an address that failed is not asked for again on the next
/// build, which is what made the guide flicker at every scroll.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
    LiveTvChannelLogo.debugForgetDeadLogos();
    PublicLogoIndex.instance.debugReset();
    addTearDown(PublicLogoIndex.instance.debugReset);
    // The image cache keeps its files on disk.
    final root = await Directory.systemTemp.createTemp('channel_logo');
    addTearDown(() => root.delete(recursive: true));
    PathProviderPlatform.instance = FakePathProvider(root);
  });

  Future<void> pumpLogo(WidgetTester tester, LiveTvChannel channel) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 60,
            child: LiveTvChannelLogo(channel: channel, client: null, fallback: (_) => Text(channel.displayName)),
          ),
        ),
      ),
    );
  }

  /// Lets the test binding answer the image requests (it refuses every one)
  /// and the error builders run.
  Future<void> settleImages(WidgetTester tester, String name) async {
    for (var i = 0; i < 60 && find.text(name).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  /// How an Illustrator export draws a station's mark: every colour in a
  /// stylesheet, the elements naming it by class. White lettering on black.
  const illustratorLogo = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generator: Adobe Illustrator -->
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
<style type="text/css">
	.st0{fill:#FFFFFF;}
</style>
<polygon points="0,0 100,0 100,100 0,100"/>
<rect class="st0" x="20" y="20" width="60" height="60"/>
</svg>''';

  /// White pixels in [bytes] drawn at 50 x 50.
  Future<int> whitePixels(WidgetTester tester, Uint8List bytes) async {
    final info = await tester.runAsync(() => vg.loadPicture(SvgBytesLoader(bytes), null));
    final image = await tester.runAsync(() => info!.picture.toImage(50, 50));
    final data = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.rawRgba));
    final pixels = data!.buffer.asUint8List();
    var white = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      if (pixels[i] > 200 && pixels[i + 1] > 200 && pixels[i + 2] > 200 && pixels[i + 3] > 200) white++;
    }
    return white;
  }

  testWidgets('an Illustrator logo keeps the colours its stylesheet gives it', (tester) async {
    final raw = Uint8List.fromList(utf8.encode(illustratorLogo));

    expect(await whitePixels(tester, raw), 0, reason: 'as it comes: a black square, the lettering lost');
    expect(await whitePixels(tester, LiveTvChannelLogo.inlineSvgClassStyles(raw)), greaterThan(500));
  });

  test('an element\'s own style still wins over its class', () {
    final inlined = utf8.decode(
      LiveTvChannelLogo.inlineSvgClassStyles(
        Uint8List.fromList(
          utf8.encode('<svg><style>.a{fill:#fff}</style><path class="a" style="fill:#f00" d="M0 0"/></svg>'),
        ),
      ),
    );
    expect(inlined, contains('style="fill:#fff;fill:#f00"'));
    expect(inlined, contains('/>'));
  });

  test('a Wikimedia thumbnail is asked for at the narrowest width that covers the drawn one', () {
    const base = 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e0/Sky_Sport_Mix_Logo_2022.svg';
    String at(int width) => '$base/${width}px-Sky_Sport_Mix_Logo_2022.svg.png';
    String servable(int width, double pixels) => LiveTvChannelLogo.servableLogoAddress(at(width), pixels: pixels);

    expect(servable(1200, 300), at(330), reason: 'the guide\'s 1200 for a logo drawn at 300');
    expect(servable(1200, 80), at(120));
    expect(servable(250, 900), at(960), reason: 'a drawing can be asked for larger than the guide did');
    expect(servable(330, 300), at(330), reason: 'already right');
    expect(servable(1920, 5000), at(1920), reason: 'nothing wider is rendered');

    const photo = 'https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Logo.png';
    expect(
      LiveTvChannelLogo.servableLogoAddress('$photo/250px-Logo.png', pixels: 900),
      '$photo/250px-Logo.png',
      reason: 'a picture has no more to give than the guide asked for',
    );
    expect(LiveTvChannelLogo.servableLogoAddress('$photo/1200px-Logo.png', pixels: 300), '$photo/330px-Logo.png');

    const elsewhere = 'https://www.tvlogolar.xyz/europa/germany/dazn1.png';
    expect(LiveTvChannelLogo.servableLogoAddress(elsewhere, pixels: 300), elsewhere, reason: 'one file, no choice');
    const original = 'https://upload.wikimedia.org/wikipedia/commons/7/71/DAZN_logo.svg';
    expect(LiveTvChannelLogo.servableLogoAddress(original, pixels: 300), original, reason: 'not a thumbnail');
  });

  test('tells SVG markup from a picture', () {
    expect(LiveTvChannelLogo.looksLikeSvg(Uint8List.fromList(utf8.encode(illustratorLogo))), isTrue);
    expect(LiveTvChannelLogo.looksLikeSvg(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])), isFalse);
  });

  testWidgets('a logo that is an SVG is drawn as one', (tester) async {
    const logo = 'https://upload.wikimedia.org/wikipedia/commons/7/71/DAZN_logo.svg';
    LiveTvChannelLogo.debugSeedSvg(logo, Uint8List.fromList(utf8.encode(illustratorLogo)));

    await pumpLogo(tester, LiveTvChannel(key: 'iptv:src:dazn', title: 'DAZN 1', thumb: logo));
    await tester.pump();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('DAZN 1'), findsNothing);
    expect(find.byType(OptimizedMediaImage), findsNothing, reason: 'the decoder is not asked for what it cannot read');
  });

  testWidgets('a dead logo falls through to the guide\'s, then to the name, and is not tried again', (tester) async {
    final channel = LiveTvChannel(
      key: 'iptv:src:sky',
      title: 'Sky Sport Mix',
      thumb: 'http://playlist.invalid/sky.png',
      guideLogo: 'http://guide.invalid/sky.png',
    );

    await pumpLogo(tester, channel);
    await settleImages(tester, 'Sky Sport Mix');
    expect(find.text('Sky Sport Mix'), findsOneWidget, reason: 'neither address loads');

    // Scrolled away and back: built afresh.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpLogo(tester, channel);
    expect(find.text('Sky Sport Mix'), findsOneWidget, reason: 'the name at once');
    expect(find.byType(OptimizedMediaImage), findsNothing, reason: 'no attempt, so no loading glyph');
  });

  testWidgets('a channel without any logo is its name, without an attempt', (tester) async {
    await pumpLogo(tester, LiveTvChannel(key: 'iptv:src:x', title: 'Kein Logo'));

    expect(find.text('Kein Logo'), findsOneWidget);
    expect(find.byType(OptimizedMediaImage), findsNothing);
  });

  group('the public collection', () {
    const paths = ['countries/germany/dmax-de.png', 'countries/germany/hd/dmax-hd-de.png'];
    final dmax = LiveTvChannel(key: 'iptv:src:dmax', title: 'DMAX HDraw');

    String? drawn(WidgetTester tester) => find
        .byType(OptimizedMediaImage)
        .evaluate()
        .map((element) => (element.widget as OptimizedMediaImage).imagePath)
        .firstOrNull;

    testWidgets('switched on, a channel with no logo that loads takes the collection\'s', (tester) async {
      await SettingsService.instance.write(SettingsService.iptvPublicLogoFallback, true);
      PublicLogoIndex.instance.debugUse(paths);

      await pumpLogo(tester, dmax);

      expect(drawn(tester), '${PublicLogoIndex.rawBase}countries/germany/hd/dmax-hd-de.png');
    });

    testWidgets('switched off, nothing is asked for', (tester) async {
      PublicLogoIndex.instance.debugUse(paths);

      await pumpLogo(tester, dmax);

      expect(drawn(tester), isNull);
      expect(find.text('DMAX HDraw'), findsOneWidget);
    });

    testWidgets('a server\'s channel is not an IPTV channel and is left alone', (tester) async {
      await SettingsService.instance.write(SettingsService.iptvPublicLogoFallback, true);
      PublicLogoIndex.instance.debugUse(paths);

      await pumpLogo(tester, LiveTvChannel(key: 'channel/7', title: 'DMAX HD', serverId: 'plex-1'));

      expect(drawn(tester), isNull);
    });
  });

  group('on Flach\'s white focus fill', () {
    final sat1 = LiveTvChannel(key: 'iptv:src:sat1', title: 'Sat.1', thumb: 'http://logos.invalid/sat1.png');

    Future<OptimizedMediaImage> drawnFocused(WidgetTester tester, {required bool focused}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: AppThemeVariant.flach),
          home: Scaffold(
            body: OckerFlatFocusInk(
              invert: focused,
              child: SizedBox(
                width: 120,
                height: 60,
                child: LiveTvChannelLogo(channel: sat1, client: null, fallback: (_) => Text(sat1.displayName)),
              ),
            ),
          ),
        ),
      );
      return tester.widget<OptimizedMediaImage>(find.byType(OptimizedMediaImage));
    }

    testWidgets('only a logo that would vanish on the white is darkened', (tester) async {
      final focused = await drawnFocused(tester, focused: true);
      expect(focused.logoToneTarget, isNotNull, reason: 'an all-white logo still turns dark');
      expect(focused.logoToneRemapMixed, isFalse, reason: 'one whose colour carries it keeps its white parts');
    });

    testWidgets('unfocused, the logo is drawn as the caller asked', (tester) async {
      final unfocused = await drawnFocused(tester, focused: false);
      expect(unfocused.logoToneTarget, isNull);
      expect(unfocused.logoToneRemapMixed, isTrue);
    });
  });
}
