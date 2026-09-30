import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'app_logger.dart';
import 'trailer_urls.dart';

/// Opens a provider trailer in the best player the device has for it.
///
/// A catalog trailer is a YouTube video, not a file: unlike a library title —
/// where the trailer is an extra the media server streams and the app plays
/// itself — there is nothing here the app's own player can open. So the job is
/// to hand it to something better than a browser tab.
///
/// On Android that means trying YouTube first. `vnd.youtube:` is the scheme
/// both the phone and the TV app register, and the explicit package intents
/// behind it cover a device where the scheme is claimed by something else.
/// The plain URL is the last resort, and on every other platform the only one.
///
/// Each candidate is attempted rather than probed: `canLaunchUrl` answers for
/// a scheme only when the manifest declares it in `<queries>`, so probing
/// would rule out an app that is installed and would have handled it.
Future<bool> openTrailer(String url) async {
  for (final candidate in _candidates(url)) {
    try {
      if (await launchUrl(Uri.parse(candidate), mode: LaunchMode.externalApplication)) return true;
    } catch (e) {
      appLogger.d('Trailer: $candidate could not be opened', error: e);
    }
  }
  return false;
}

Iterable<String> _candidates(String url) sync* {
  if (Platform.isAndroid) {
    if (youTubeVideoId(url) case final id?) {
      yield 'vnd.youtube:$id';
      for (final package in const ['com.google.android.youtube.tv', 'com.google.android.youtube']) {
        yield 'intent:$url#Intent;action=android.intent.action.VIEW;package=$package;end';
      }
    }
  }
  yield url;
}
