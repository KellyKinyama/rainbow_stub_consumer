// Phase L acceptance — RFC 6120 §8.2.3 IQ request/response correlation
// on the client. Exercises sendIq() completion, error, timeout, and
// non-matching pass-through via the offline `debugRouteStanza` hook.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/rainbow/xmpp_client.dart';
import 'package:xml/xml.dart';

RainbowXmppClient _makeClient() =>
    RainbowXmppClient(wsUrl: Uri.parse('ws://x/'), domain: 'localhost');

XmlElement _parse(String xml) => XmlDocument.parse(xml).rootElement;

void main() {
  test('sendIq completes with the matching result iq', () async {
    final c = _makeClient();
    final fut = c.sendIq(
      type: 'get',
      payload: '<ping xmlns="urn:xmpp:ping"/>',
      id: 'q1',
    );
    c.debugRouteStanza(_parse('<iq type="result" id="q1"/>'));
    final resp = await fut;
    expect(resp.getAttribute('type'), 'result');
    expect(resp.getAttribute('id'), 'q1');
  });

  test('sendIq throws XmppIqError on an error response', () async {
    final c = _makeClient();
    final fut = c.sendIq(type: 'get', id: 'q2');
    final expectation = expectLater(fut, throwsA(isA<XmppIqError>()));
    c.debugRouteStanza(
      _parse(
        '<iq type="error" id="q2">'
        '<error type="cancel">'
        '<service-unavailable xmlns="urn:ietf:params:xml:ns:xmpp-stanzas"/>'
        '</error></iq>',
      ),
    );
    await expectation;
  });

  test('sendIq times out when no reply arrives', () async {
    final c = _makeClient();
    final fut = c.sendIq(
      type: 'get',
      id: 'q3',
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(fut, throwsA(isA<TimeoutException>()));
  });

  test('a result iq with a non-matching id does not complete the future', () async {
    final c = _makeClient();
    var settled = false;
    final fut = c.sendIq(type: 'get', id: 'q4');
    unawaited(fut.then((_) => settled = true, onError: (_) => settled = true));

    c.debugRouteStanza(_parse('<iq type="result" id="someone-else"/>'));
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);

    // Settle it so the pending timer doesn't linger past the test.
    c.debugRouteStanza(_parse('<iq type="result" id="q4"/>'));
    await fut;
  });
}
