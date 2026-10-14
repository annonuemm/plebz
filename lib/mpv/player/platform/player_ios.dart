import '../player_native.dart';
import '../video_rect_support.dart';

/// The iPhone, iPad and Apple TV player (Plebz): libmpv drawing into an
/// `AVSampleBufferDisplayLayer` that sits *behind* the Flutter view.
///
/// As on the Mac ([PlayerMacOS]), that layer needs to be told where to stand:
/// window-sized is right for the full-screen player and wrong for the guide's
/// preview beside its schedule. `Video` measures the place for any
/// [VideoRectTarget], and the native side (`ios/Runner/MpvPlayer`) frames the
/// layer's container there — on the main window only; an external display
/// keeps the whole screen.
class PlayerIOS extends PlayerNative with VideoRectSupport {}
