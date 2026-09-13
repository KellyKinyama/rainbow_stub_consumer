// Phase N acceptance — RFC 6121 §3 presence subscription events on the
// client. Verifies subscription stanzas surface as XmppSubscription and
// that ordinary presence still flows as XmppPresenceUpdate.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/rainbow/xmpp_client.dart';
import 'package:xml/xml.dart';

RainbowXmppClient _makeClient() =>
    RainbowXmppClient(wsUrl: Uri.parse('ws://x/'), domain: 'localhost');

XmlElement _parse(String xml) => XmlDocument.parse(xml).rootElement;

void main() {
  test('inbound subscribe presence emits XmppSubscription', () async {
    final c = _makeClient();
    final subs = <XmppSubscription>[];
    final sub = c.events
        .where((e) => e is XmppSubscription)
        .cast<XmppSubscription>()
        .listen(subs.add);

    c.debugRouteStanza(
      _parse('<presence from="alice@localhost" type="subscribe"/>'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(subs, hasLength(1));
    expect(subs.first.type, 'subscribe');
    expect(subs.first.fromBare, 'alice@localhost');
    await sub.cancel();
  });

  test('ordinary presence still emits XmppPresenceUpdate', () async {
    final c = _makeClient();
    final updates = <XmppPresenceUpdate>[];
    final sub = c.events
        .where((e) => e is XmppPresenceUpdate)
        .cast<XmppPresenceUpdate>()
        .listen(updates.add);

    c.debugRouteStanza(
      _parse('<presence from="bob@localhost/web"><show>away</show></presence>'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(updates, hasLength(1));
    expect(updates.first.fromBare, 'bob@localhost');
    expect(updates.first.show, 'away');
    await sub.cancel();
  });
}
