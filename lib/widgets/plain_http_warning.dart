import 'package:flutter/widgets.dart';

import '../i18n/strings.g.dart';
import '../utils/dialogs.dart';
import '../utils/network_locality.dart';

/// Before credentials go to [url]: true straight away unless that is plain
/// HTTP across the internet, in which case the person decides, warned.
Future<bool> confirmPlainHttpIfNeeded(BuildContext context, String url) async {
  if (!isPlainHttpOverInternet(url)) return true;
  final host = Uri.tryParse(url)?.host ?? url;
  return showConfirmDialog(
    context,
    title: t.addServer.plainHttpTitle,
    message: t.addServer.plainHttpMessage(host: host),
    confirmText: t.addServer.plainHttpContinue,
    cancelText: t.common.cancel,
    isDestructive: true,
  );
}
