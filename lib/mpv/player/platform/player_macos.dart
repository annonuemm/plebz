import '../player_native.dart';
import '../video_rect_support.dart';

/// The Mac player: libmpv through MPVKit, drawing into a `CAMetalLayer` that
/// sits *behind* the Flutter view.
///
/// That layer is why this is a [VideoRectSupport] and plain [PlayerNative] is
/// not enough. The Flutter view is cleared to transparent
/// (`MainFlutterWindow`), so whatever the layer covers shows through wherever
/// Flutter draws nothing — which is exactly right for a full-screen picture
/// and exactly wrong for a preview standing next to a programme guide, where
/// a window-sized layer would put the picture behind the whole page.
///
/// iOS and tvOS stay on the bare [PlayerNative]: they have no second place to
/// put a picture, so there is no geometry to report.
class PlayerMacOS extends PlayerNative with VideoRectSupport {}
