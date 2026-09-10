import 'package:web_socket_channel/web_socket_channel.dart';

import '_xmpp_socket_io.dart'
    if (dart.library.html) '_xmpp_socket_web.dart'
    if (dart.library.js_interop) '_xmpp_socket_web.dart';

/// Opens the XMPP WebSocket. Native builds use `dart:io` so they can
/// honour [acceptSelfSignedCerts]; web builds go through the browser's
/// WebSocket API and ignore that flag (the browser controls TLS trust).
Future<WebSocketChannel> openXmppSocket(
  Uri uri, {
  required bool acceptSelfSignedCerts,
  List<String> protocols = const ['xmpp'],
}) => platformOpenXmppSocket(
  uri,
  acceptSelfSignedCerts: acceptSelfSignedCerts,
  protocols: protocols,
);
