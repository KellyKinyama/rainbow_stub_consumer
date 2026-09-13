import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> platformOpenXmppSocket(
  Uri uri, {
  required bool acceptSelfSignedCerts,
  List<String> protocols = const ['xmpp'],
}) async {
  HttpClient? io;
  if (acceptSelfSignedCerts) {
    io = HttpClient()..badCertificateCallback = (_, _, _) => true;
  }
  final ch = IOWebSocketChannel.connect(
    uri,
    protocols: protocols,
    customClient: io,
  );
  await ch.ready;
  return ch;
}
