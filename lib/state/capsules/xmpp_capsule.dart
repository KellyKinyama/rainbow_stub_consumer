import 'package:rearch/rearch.dart';

import '../../rainbow/xmpp_client.dart';
import 'config_capsule.dart';

/// Long-lived [RainbowXmppClient] tied to the current [AppConfig].
///
/// Disposal calls [RainbowXmppClient.disconnect] to close the underlying
/// websocket cleanly.
RainbowXmppClient xmppCapsule(CapsuleHandle use) {
  final config = use(configCapsule);
  return use.disposable<RainbowXmppClient>(
    () => RainbowXmppClient(wsUrl: config.wsUrl, domain: config.xmppDomain),
    (client) {
      // fire-and-forget: disposal is synchronous, disconnect is async but
      // sends a terminating </close/> stanza and closes the socket.
      // Any error during shutdown is intentionally swallowed.
      client.disconnect();
    },
    [config],
  );
}

/// Convenience: expose the XMPP client's broadcast event stream so
/// downstream capsules can `use.stream(...)` on it without pulling the
/// whole client in.
Stream<XmppEvent> xmppEventsCapsule(CapsuleHandle use) =>
    use(xmppCapsule).events;
