import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> platformOpenXmppSocket(
  Uri uri, {
  required bool acceptSelfSignedCerts,
  List<String> protocols = const ['xmpp'],
}) async {
  // Browser controls TLS trust; the self-signed-cert flag is irrelevant.
  final ch = WebSocketChannel.connect(uri, protocols: protocols);
  await ch.ready;
  return ch;
}
