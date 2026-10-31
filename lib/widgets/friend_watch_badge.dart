import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../media/media_item.dart';
import '../redesign/ocker_skin.dart';
import '../services/friends/friends_activity.dart';
import '../theme/mono_tokens.dart';

/// The friend who watched a title, on its poster (Plebz): their picture, their
/// name and when, on a capsule across the poster's foot.
///
/// Bottom left, clear of the bottom-right corner the availability check and
/// its ring own. The capsule follows the look: a dark glass with a lit hairline
/// under "Glas", a plain wash under "Flach", and the catalog badges' black
/// elsewhere — so it reads on any artwork without a shadow.
class FriendWatchBadge extends StatelessWidget {
  const FriendWatchBadge({super.key, required this.mark});

  final FriendWatchMark mark;

  /// The badge for [item], or nothing when no friend rides along.
  static Widget? forItem(MediaItem item) {
    final mark = friendWatchOf(item);
    return mark == null ? null : FriendWatchBadge(mark: mark);
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final glass = ockerGlass(context) && !ockerFlat(context);
    final flat = ockerFlat(context);
    return Positioned(
      key: const Key('friend-watch-badge'),
      left: 6,
      right: 30,
      bottom: 6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Sized by the poster, not the screen: a phone grid's poster and a
          // television's carry the same proportion of words.
          final size = (constraints.maxWidth * 0.082).clamp(9.0, 15.0);
          final avatar = size * 1.7;
          return Align(
            alignment: Alignment.bottomLeft,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: flat ? tk.bg.withValues(alpha: 0.86) : Colors.black.withValues(alpha: glass ? 0.62 : 0.76),
                shape: StadiumBorder(
                  side: glass ? BorderSide(color: Colors.white.withValues(alpha: 0.22), width: 1) : BorderSide.none,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(size * 0.25, size * 0.25, size * 0.7, size * 0.25),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FriendAvatar(name: mark.name, initial: mark.initial, url: mark.avatarUrl, size: avatar),
                    SizedBox(width: size * 0.45),
                    Flexible(
                      child: Text(
                        '${mark.name} · ${friendWatchWhen(mark.at)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: flat ? tk.text : Colors.white,
                          fontSize: size,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A friend's round picture, or their initial on a colour of their own when
/// Plex has none to give.
class FriendAvatar extends StatelessWidget {
  const FriendAvatar({super.key, required this.name, required this.initial, this.url, required this.size});

  final String name;
  final String initial;
  final String? url;
  final double size;

  /// The same friend gets the same colour everywhere.
  static Color colourFor(String name) {
    const colours = [
      Color(0xFFC0587E),
      Color(0xFF3D7FB8),
      Color(0xFF4F9A6B),
      Color(0xFFB07A2E),
      Color(0xFF7A62C9),
      Color(0xFF2E9AA0),
    ];
    return colours[name.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % colours.length];
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colourFor(name), shape: BoxShape.circle),
      child: Text(
        initial,
        style: TextStyle(color: Colors.white, fontSize: size * 0.48, fontWeight: FontWeight.w700, height: 1),
      ),
    );
    final address = url;
    if (address == null) return fallback;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image(
          image: ResizeImage(CachedNetworkImageProvider(address), width: 96, height: 96, allowUpscaling: false),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
              frame == null && !wasSynchronouslyLoaded ? fallback : child,
        ),
      ),
    );
  }
}
