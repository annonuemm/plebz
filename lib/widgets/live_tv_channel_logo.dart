import 'dart:async';
import '../utils/tone_mapped_logo_image.dart';
import '../theme/mono_tokens.dart';
import '../redesign/ocker_skin.dart' show OckerFlatFocusInk, OckerKeepColours;
import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../media/media_server_client.dart';
import '../models/livetv_channel.dart';
import '../services/image_cache_service.dart';
import '../services/iptv/public_logo_index.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import '../utils/media_image_helper.dart';
import 'optimized_media_image.dart';

/// A channel's logo, and what stands in when it has none that loads.
///
/// Tries the channel's own logo, then the one its IPTV guide names
/// ([LiveTvChannel.guideLogo]), then builds [fallback] — usually the name.
/// Providers list plenty of dead logos, and to the viewer a dead logo is no
/// logo at all.
///
/// An address that failed is left alone for a while. A guide row is built
/// anew every time it scrolls into view, and each fresh attempt showed the
/// image's loading glyph until the address failed again: a flicker on every
/// channel with a dead logo, at every scroll. Nothing is drawn while a logo
/// loads, for the same reason.
///
/// A logo may be an SVG — Wikipedia serves many stations' marks that way,
/// and playlists link them straight — which the image decoder cannot read.
/// An address ending in `.svg` is drawn as one; any other that fails to
/// decode is looked at once more, in case it is an SVG under another name.
class LiveTvChannelLogo extends StatelessWidget {
  const LiveTvChannelLogo({
    super.key,
    required this.channel,
    required this.client,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.logoToneTarget,
  });

  final LiveTvChannel channel;

  /// Builds a server-relative logo's address; an IPTV logo is a full one and
  /// needs none.
  final MediaServerClient? client;
  final WidgetBuilder fallback;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Color? logoToneTarget;

  /// How long a logo that failed is not asked for again. Long enough that
  /// scrolling a guide does not keep asking; short enough that a logo server
  /// that was down for a moment gets another chance in the same session — a
  /// television app can stay open for days.
  static const deadFor = Duration(hours: 1);

  static final Map<String, DateTime> _deadUntil = {};

  /// SVG logos already read, and the reads in flight — a logo shows in many
  /// rows and on many screens, and is read once.
  static final Map<String, Uint8List> _svgBytes = {};
  static final Map<String, Future<Uint8List?>> _svgReads = {};

  @visibleForTesting
  static void debugForgetDeadLogos() {
    _deadUntil.clear();
    _svgBytes.clear();
    _svgReads.clear();
  }

  /// Puts [bytes] where a read of [logo] would, for a test with no network.
  @visibleForTesting
  static void debugSeedSvg(String logo, Uint8List bytes) => _svgBytes[logo] = inlineSvgClassStyles(bytes);

  static final _styleBlock = RegExp(r'<style[^>]*>([\s\S]*?)</style>', caseSensitive: false);
  static final _cssRule = RegExp(r'([^{}]+)\{([^{}]*)\}');
  static final _classSelector = RegExp(r'^\.([\w-]+)$');
  static final _taggedWithClass = RegExp(r'''<([a-zA-Z][\w:.-]*)(\s[^<>]*?)?\sclass=(["'])([^"']*)\3([^<>]*)>''');
  static final _inlineStyle = RegExp(r'''\sstyle=(["'])([^"']*)\1''');

  /// [bytes] with the rules of their `<style>` block written onto the
  /// elements that name them.
  ///
  /// The SVG renderer reads a `style` attribute but not a stylesheet, and
  /// Illustrator — where a good share of stations' logos were drawn — puts
  /// every colour in one: `.st0{fill:#FFFFFF;}` and `class="st0"`. Drawn as
  /// it comes, DAZN's white lettering was a black square. Plain class rules
  /// only, which is all such an export holds; the element's own `style`
  /// still wins, as it would in a browser.
  @visibleForTesting
  static Uint8List inlineSvgClassStyles(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final rules = <String, String>{};
    for (final block in _styleBlock.allMatches(text)) {
      final css = block
          .group(1)!
          .replaceAll('<![CDATA[', '')
          .replaceAll(']]>', '')
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
      for (final rule in _cssRule.allMatches(css)) {
        final declarations = rule.group(2)!.trim();
        if (declarations.isEmpty) continue;
        for (final selector in rule.group(1)!.split(',')) {
          final name = _classSelector.firstMatch(selector.trim())?.group(1);
          if (name == null) continue;
          final before = rules[name];
          rules[name] = before == null ? declarations : '$before;$declarations';
        }
      }
    }
    if (rules.isEmpty) return bytes;

    final inlined = text.replaceAllMapped(_taggedWithClass, (match) {
      final fromClasses = [for (final name in match.group(4)!.split(RegExp(r'\s+'))) ?rules[name]];
      if (fromClasses.isEmpty) return match.group(0)!;
      var attributes = '${match.group(2) ?? ''}${match.group(5)}';
      var style = fromClasses.join(';');
      final own = _inlineStyle.firstMatch(attributes);
      if (own != null) {
        style = '$style;${own.group(2)}';
        attributes = attributes.replaceFirst(own.group(0)!, '');
      }
      final selfClosing = attributes.trimRight().endsWith('/');
      if (selfClosing) attributes = attributes.trimRight().substring(0, attributes.trimRight().length - 1);
      return '<${match.group(1)}$attributes style="$style"${selfClosing ? '/' : ''}>';
    });
    return Uint8List.fromList(utf8.encode(inlined));
  }

  static void _markDead(String logo) => _deadUntil[logo] = DateTime.now().add(deadFor);

  /// An address whose path names an SVG file.
  static bool _namesSvg(String logo) => Uri.tryParse(logo)?.path.toLowerCase().endsWith('.svg') ?? false;

  /// Whether [bytes] are SVG markup: `<svg` near the start, after whatever
  /// XML prolog, doctype or comment comes first.
  @visibleForTesting
  static bool looksLikeSvg(Uint8List bytes) {
    final head = String.fromCharCodes(bytes.take(1024)).toLowerCase();
    return head.contains('<svg');
  }

  /// Reads [logo] through the artwork cache — on disk, with the header every
  /// artwork request carries — and gives its bytes if they are SVG.
  static Future<Uint8List?> _readSvg(String logo) => _svgReads.putIfAbsent(logo, () async {
    try {
      await for (final response in PlexImageCacheManager.instance.getFileStream(
        logo,
        key: 'channel_logo_svg:$logo',
        headers: const {'User-Agent': 'Plezy'},
      )) {
        if (response is! FileInfo) continue;
        final bytes = await response.file.readAsBytes();
        if (!looksLikeSvg(bytes)) return null;
        return _svgBytes[logo] = inlineSvgClassStyles(bytes);
      }
    } catch (e) {
      appLogger.d('Channel logo $logo could not be read', error: e);
    }
    // Not kept: after [deadFor] the address is asked for again.
    unawaited(Future<void>.microtask(() => _svgReads.remove(logo)));
    return null;
  });

  static final _wikimediaThumb = RegExp(r'^(https?://upload\.wikimedia\.org/.+/thumb/.+/)(\d+)px-([^/?#]+)$');

  /// The widths Wikimedia still renders thumbnails at. Since 2025 any other
  /// answers with an error page, for every client — and guides carry
  /// thumbnail addresses written years ago at whatever width their author
  /// liked ("1200px-Sky_Sport_Mix_Logo_2022.svg.png").
  static const _wikimediaWidths = [20, 40, 60, 120, 250, 330, 500, 960, 1280, 1920];

  /// Used where a logo is drawn without a width of its own and its box has
  /// none to measure either.
  static const _unknownDrawnWidth = 250.0;

  /// [logo] as an address that fetches what [pixels] — the width the logo is
  /// drawn at, in device pixels — needs, and no more.
  ///
  /// Only where the server lets the size be chosen, which among logo hosts
  /// means Wikimedia: its thumbnail addresses carry their width. Asked for at
  /// the narrowest width it renders that covers [pixels] — a guide's
  /// "1200px-…" for a logo drawn at 300 is four times the width and some
  /// sixteen times the data. Never wider than the address asked for when the
  /// original is a picture rather than a drawing: a raster image has no more
  /// to give. Every other address is left as it is; its server holds one
  /// file.
  @visibleForTesting
  static String servableLogoAddress(String logo, {required double pixels}) {
    final match = _wikimediaThumb.firstMatch(logo);
    final asked = int.tryParse(match?.group(2) ?? '');
    if (match == null || asked == null) return logo;
    final name = match.group(3)!;
    final fitting = _wikimediaWidths.firstWhere((width) => width >= pixels, orElse: () => _wikimediaWidths.last);
    final drawing = name.toLowerCase().contains('.svg.');
    var width = fitting;
    if (!drawing && width > asked) {
      // Not larger than asked, and still a width Wikimedia renders.
      width = _wikimediaWidths.lastWhere((allowed) => allowed <= asked, orElse: () => _wikimediaWidths.first);
    }
    return width == asked ? logo : '${match.group(1)}${width}px-$name';
  }

  static bool _isDead(String logo) {
    final until = _deadUntil[logo];
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _deadUntil.remove(logo);
    return false;
  }

  List<String> _candidates(double pixels) {
    final candidates = <String>[];
    for (final logo in [channel.thumb, channel.guideLogo]) {
      final trimmed = logo?.trim();
      if (trimmed == null || trimmed.isEmpty) continue;
      final address = servableLogoAddress(trimmed, pixels: pixels);
      if (candidates.contains(address) || _isDead(address)) continue;
      if (client == null && !MediaImageHelper.isSelfContainedImageUrl(address)) continue;
      candidates.add(address);
    }
    return candidates;
  }

  /// The tone a logo is drawn in: the caller's, or — on a flat focus fill,
  /// which is white (Plebz) — darkened where the logo is light, as a white
  /// wordmark would vanish there. Its other colours stay as they are.
  Color? _toneAt(BuildContext context) => OckerFlatFocusInk.invertingAt(context)
      ? channelLogoToneTargetFor(surface: Colors.white, foreground: tokens(context).bg)
      : logoToneTarget;

  /// Whether a light mark beside real colour is darkened too. Not on a flat
  /// focus fill: there only a logo that would vanish on the white is — an
  /// all-white wordmark, or one with a small accent — while one whose colour
  /// carries it (Sat.1's ball) keeps its white parts. Darkened, those read as
  /// a negative of the logo (the viewer's call, 2026-10-10).
  bool _remapsMixedAt(BuildContext context) => !OckerFlatFocusInk.invertingAt(context);

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final drawnWidth = width;
    if (drawnWidth != null && drawnWidth.isFinite) return _logo(context, _candidates(drawnWidth * ratio), 0);
    // No width given: the box it is drawn in says how wide it can be.
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.maxWidth.isFinite ? constraints.maxWidth : _unknownDrawnWidth;
        return _logo(context, _candidates(box * ratio), 0);
      },
    );
  }

  Widget _logo(BuildContext context, List<String> candidates, int index) {
    if (index >= candidates.length) return _fromCollection(context);
    final logo = candidates[index];
    Widget next(BuildContext context) {
      _markDead(logo);
      return _logo(context, candidates, index + 1);
    }

    if (_svgBytes[logo] case final bytes?) return OckerKeepColours(child: _svg(bytes, next));
    // Named an SVG: straight there, no attempt the decoder is sure to fail.
    if (_namesSvg(logo)) return OckerKeepColours(child: _svgRead(logo, next));
    return OptimizedMediaImage.thumb(
      key: ValueKey(logo),
      client: client,
      imagePath: logo,
      width: width,
      height: height,
      fit: fit,
      logoToneTarget: _toneAt(context),
      logoToneRemapMixed: _remapsMixedAt(context),
      placeholder: (_, _) => const SizedBox.shrink(),
      // Not an image the decoder knows: perhaps an SVG under another name.
      errorWidget: (context, _, _) => _svgRead(logo, next),
    );
  }

  /// The last stop before [fallback], and only where the viewer switched it
  /// on: the public collection's logo for an IPTV channel whose own logo and
  /// whose guide's both failed. The name stands until the collection's file
  /// list is there — it is read once a week at most, and only when a channel
  /// first needs it.
  Widget _fromCollection(BuildContext context) {
    final wanted =
        channel.key.startsWith('iptv:') &&
        (SettingsService.instanceOrNull?.read(SettingsService.iptvPublicLogoFallback) ?? false);
    if (!wanted) return fallback(context);
    final collection = PublicLogoIndex.instance..ensureLoaded();
    return ValueListenableBuilder<bool>(
      valueListenable: collection.ready,
      builder: (context, ready, _) {
        final logo = ready ? collection.logoFor(channel.displayName) ?? collection.logoFor(channel.identifier) : null;
        if (logo == null || _isDead(logo)) return fallback(context);
        return OptimizedMediaImage.thumb(
          key: ValueKey(logo),
          imagePath: logo,
          width: width,
          height: height,
          fit: fit,
          logoToneTarget: _toneAt(context),
          logoToneRemapMixed: _remapsMixedAt(context),
          placeholder: (_, _) => const SizedBox.shrink(),
          errorWidget: (context, _, _) {
            _markDead(logo);
            return fallback(context);
          },
        );
      },
    );
  }

  Widget _svgRead(String logo, WidgetBuilder next) => FutureBuilder<Uint8List?>(
    key: ValueKey('svg:$logo'),
    future: _readSvg(logo),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const SizedBox.shrink();
      final bytes = snapshot.data;
      return bytes == null ? next(context) : _svg(bytes, next);
    },
  );

  Widget _svg(Uint8List bytes, WidgetBuilder next) => SvgPicture.memory(
    bytes,
    width: width,
    height: height,
    fit: fit,
    placeholderBuilder: (_) => const SizedBox.shrink(),
    errorBuilder: (context, _, _) => next(context),
  );
}
