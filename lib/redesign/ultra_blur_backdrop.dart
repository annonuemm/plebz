import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../focus/card_focus_scope.dart';
import '../media/catalog_item_ref.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/ultra_blur_colors.dart';
import '../models/catalog/catalog_item.dart';
import '../services/plex_client.dart';
import '../utils/app_logger.dart';

/// Where the colours of a title's artwork come from: its own Plex server for a
/// library title, any connected Plex server for one of Plex's catalogue.
typedef UltraBlurClientLookup = ({PlexClient? Function(String serverId) owner, PlexClient? Function() any});

/// The colours behind the screen, following the poster that holds focus —
/// Plex's "UltraBlur", for Plex titles only (a test, behind a switch).
///
/// Nothing is blurred: the server derives four corner colours from a title's
/// artwork once, and the screen blends them corner to corner. The box draws
/// one small gradient; the cost is a request per title, remembered.
class UltraBlurAmbient extends ChangeNotifier implements ValueListenable<UltraBlurColors?> {
  UltraBlurAmbient(this._clients);

  final UltraBlurClientLookup _clients;

  /// Holding a key down walks a row at the repeat rate; only where it stops
  /// is worth a request and a change of colour. Long enough that stepping
  /// through a row poster by poster does not change the colour at every one
  /// (the user's call: 180 ms was too eager).
  static const settleDelay = Duration(milliseconds: 400);

  static const int _cacheSize = 400;

  /// Shared across shells: a title's colours do not change in a session.
  static final LinkedHashMap<String, UltraBlurColors?> _cache = LinkedHashMap();

  UltraBlurColors? _value;
  Timer? _settle;
  int _generation = 0;
  bool _disposed = false;

  @override
  UltraBlurColors? get value => _value;

  void _set(UltraBlurColors? colors) {
    if (_disposed || colors == _value) return;
    _value = colors;
    notifyListeners();
  }

  /// [item] has taken focus. A title that is not Plex's lets the ground show
  /// again.
  void report(MediaItem item) {
    final generation = ++_generation;
    _settle?.cancel();
    _settle = Timer(settleDelay, () => unawaited(_resolve(item, generation)));
  }

  Future<void> _resolve(MediaItem item, int generation) async {
    final request = _requestFor(item);
    if (request == null) {
      _set(null);
      return;
    }
    final (:client, :url, :key) = request;
    if (_cache.containsKey(key)) {
      final colors = _cache.remove(key);
      _cache[key] = colors;
      _set(colors);
      return;
    }
    UltraBlurColors? colors;
    try {
      colors = await client.fetchUltraBlurColors(url);
    } catch (error) {
      appLogger.d('UltraBlur: no colours for $url', error: error);
    }
    _cache[key] = colors;
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
    if (generation == _generation) _set(colors);
  }

  ({PlexClient client, String url, String key})? _requestFor(MediaItem item) {
    final url = _nonEmpty(item.artPath) ?? _nonEmpty(item.thumbPath);
    if (url == null) return null;
    if (item.isCatalogItem) {
      if (item.catalogItem?.source != CatalogSourceId.plex) return null;
      final client = _clients.any();
      return client == null ? null : (client: client, url: url, key: url);
    }
    final serverId = item.serverId;
    if (item.backend != MediaBackend.plex || serverId == null) return null;
    final client = _clients.owner(serverId);
    return client == null ? null : (client: client, url: url, key: '$serverId|$url');
  }

  static String? _nonEmpty(String? value) => value == null || value.isEmpty ? null : value;

  @visibleForTesting
  static void debugClearCache() => _cache.clear();

  /// Test seam: colours as if the server had answered.
  @visibleForTesting
  void debugShow(UltraBlurColors? colors) => _set(colors);

  @override
  void dispose() {
    _disposed = true;
    _settle?.cancel();
    super.dispose();
  }
}

/// Hands the ambient colours down to the posters that report to them. Null
/// [ambient] — the switch off, or a host without the redesign's shell — makes
/// every report a no-op.
class UltraBlurScope extends InheritedWidget {
  const UltraBlurScope({super.key, required this.ambient, required super.child});

  final UltraBlurAmbient? ambient;

  /// The ambient colours, without subscribing — for reporters.
  static UltraBlurAmbient? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<UltraBlurScope>()?.ambient;

  /// The ambient colours, rebuilding [context] when they are switched on or
  /// off — for a card deciding whether to report at all.
  static UltraBlurAmbient? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UltraBlurScope>()?.ambient;

  @override
  bool updateShouldNotify(UltraBlurScope oldWidget) => ambient != oldWidget.ambient;
}

/// [child], reporting [item] whenever the card's focus wrapper shows focus
/// ([CardFocusScope]) — and nothing more while the ambient colours are off.
class UltraBlurCardReporter extends StatelessWidget {
  const UltraBlurCardReporter({super.key, required this.item, required this.child});

  final MediaItem item;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (UltraBlurScope.of(context) == null) return child;
    return UltraBlurFocusReporter(item: item, focused: CardFocusScope.maybeOf(context) ?? false, child: child);
  }
}

/// Reports [item] to the ambient colours whenever the card around it shows
/// focus. [focused] comes from the card's own focus wrapper.
class UltraBlurFocusReporter extends StatefulWidget {
  const UltraBlurFocusReporter({super.key, required this.item, required this.focused, required this.child});

  final MediaItem item;
  final bool focused;
  final Widget child;

  @override
  State<UltraBlurFocusReporter> createState() => _UltraBlurFocusReporterState();
}

class _UltraBlurFocusReporterState extends State<UltraBlurFocusReporter> {
  @override
  void initState() {
    super.initState();
    if (widget.focused) _reportSoon();
  }

  @override
  void didUpdateWidget(UltraBlurFocusReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused && (!oldWidget.focused || oldWidget.item.id != widget.item.id)) _reportSoon();
  }

  /// After the frame: the report changes the ground, which must not be asked
  /// for in the middle of a build.
  void _reportSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focused) return;
      UltraBlurScope.read(context)?.report(widget.item);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The ambient colours painted across the whole box: the four corners blended
/// into each other, crossfading when they change, gone (the glass ground
/// showing) while there are none.
///
/// The blend is a 2×2 image of the corners stretched over the screen with
/// linear filtering, sampled from pixel centre to pixel centre — exactly the
/// corner-to-corner blend, as one textured quad, the cheapest thing the box
/// can draw.
class UltraBlurLayer extends StatefulWidget {
  const UltraBlurLayer({super.key, required this.colors, this.dim = defaultDim});

  final ValueListenable<UltraBlurColors?> colors;

  /// How far the corners are taken towards black, so light text keeps its
  /// contrast over a light poster.
  final double dim;

  /// The shell's ground, which only ever has a scrim of black over it where
  /// words stand on it.
  static const double defaultDim = 0.3;

  static const Duration crossfade = Duration(milliseconds: 450);

  @override
  State<UltraBlurLayer> createState() => _UltraBlurLayerState();
}

class _UltraBlurLayerState extends State<UltraBlurLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(vsync: this, duration: UltraBlurLayer.crossfade);
  ui.Image? _current;
  ui.Image? _previous;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.colors.addListener(_onColors);
    _fade.addStatusListener((status) {
      if (status != AnimationStatus.completed || _previous == null) return;
      // Through a rebuild: the painter on screen still holds the old image,
      // and painting one that has been let go of draws nothing at all — the
      // colours vanished the moment the fade was done.
      final faded = _previous;
      setState(() => _previous = null);
      _release(faded);
    });
    _onColors();
  }

  @override
  void didUpdateWidget(UltraBlurLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.colors != widget.colors) {
      oldWidget.colors.removeListener(_onColors);
      widget.colors.addListener(_onColors);
      _onColors();
    }
  }

  Future<void> _onColors() async {
    final generation = ++_generation;
    final colors = widget.colors.value;
    final image = colors == null ? null : await _imageOf(colors, widget.dim);
    if (!mounted || generation != _generation) {
      image?.dispose();
      return;
    }
    final dropped = _previous;
    setState(() {
      _previous = _current;
      _current = image;
    });
    _release(dropped);
    unawaited(_fade.forward(from: 0));
  }

  /// Let [image] go once the frame that stops painting it is done.
  void _release(ui.Image? image) {
    if (image == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  static Future<ui.Image> _imageOf(UltraBlurColors colors, double dim) {
    final pixels = Uint8List(16);
    void put(int index, Color color) {
      final c = Color.lerp(color, const Color(0xFF000000), dim)!;
      pixels[index * 4] = (c.r * 255).round();
      pixels[index * 4 + 1] = (c.g * 255).round();
      pixels[index * 4 + 2] = (c.b * 255).round();
      pixels[index * 4 + 3] = 255;
    }

    put(0, colors.topLeft);
    put(1, colors.topRight);
    put(2, colors.bottomLeft);
    put(3, colors.bottomRight);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, 2, 2, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  @override
  void dispose() {
    widget.colors.removeListener(_onColors);
    _fade.dispose();
    _current?.dispose();
    _previous?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _UltraBlurPainter(current: _current, previous: _previous, fade: _fade),
      size: Size.infinite,
    ),
  );
}

class _UltraBlurPainter extends CustomPainter {
  _UltraBlurPainter({required this.current, required this.previous, required this.fade}) : super(repaint: fade);

  final ui.Image? current;
  final ui.Image? previous;
  final Animation<double> fade;

  /// Pixel centre to pixel centre: the corners land exactly on the corners.
  static const Rect _source = Rect.fromLTRB(0.5, 0.5, 1.5, 1.5);

  @override
  void paint(Canvas canvas, Size size) {
    final destination = Offset.zero & size;
    final t = Curves.easeInOut.transform(fade.value);
    final paint = Paint()..filterQuality = FilterQuality.low;
    final previous = this.previous;
    final current = this.current;
    if (previous != null) {
      // Under a new colour the old one stays whole and the new one fades in
      // over it; with none to come, the old one fades out to the ground.
      final opacity = current == null ? 1 - t : 1.0;
      canvas.drawImageRect(previous, _source, destination, paint..color = Color.fromRGBO(0, 0, 0, opacity));
    }
    if (current != null) {
      canvas.drawImageRect(current, _source, destination, paint..color = Color.fromRGBO(0, 0, 0, t));
    }
  }

  @override
  bool shouldRepaint(_UltraBlurPainter oldDelegate) =>
      oldDelegate.current != current || oldDelegate.previous != previous;
}
