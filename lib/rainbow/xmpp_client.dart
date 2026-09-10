import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xml/xml.dart';

class XmppEvent {
  const XmppEvent();
}

class XmppConnected extends XmppEvent {
  const XmppConnected(this.jid);
  final String jid;
}

class XmppDisconnected extends XmppEvent {
  const XmppDisconnected(this.reason);
  final String reason;
}

class XmppChatMessage extends XmppEvent {
  const XmppChatMessage({
    required this.from,
    required this.to,
    required this.body,
    required this.stanzaId,
    required this.isGroupChat,
  });
  final String from;
  final String to;
  final String body;
  final String stanzaId;
  final bool isGroupChat;
}

class XmppPresenceUpdate extends XmppEvent {
  const XmppPresenceUpdate({
    required this.fromBare,
    required this.show,
    this.status,
  });
  final String fromBare;
  final String show;
  final String? status;
}

class RainbowXmppClient {
  RainbowXmppClient({
    required this.wsUrl,
    required this.domain,
    this.acceptSelfSignedCerts = true,
  });

  final Uri wsUrl;
  final String domain;
  final bool acceptSelfSignedCerts;

  final _events = StreamController<XmppEvent>.broadcast();
  Stream<XmppEvent> get events => _events.stream;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String _fullJid = '';
  String get fullJid => _fullJid;
  String get bareJid => _fullJid.contains('/')
      ? _fullJid.substring(0, _fullJid.indexOf('/'))
      : _fullJid;
  bool get isConnected => _channel != null && _fullJid.isNotEmpty;

  Future<void> connect({
    required String email,
    required String saslPassword,
    String resource = 'flutter',
  }) async {
    HttpClient? io;
    if (acceptSelfSignedCerts) {
      io = HttpClient()..badCertificateCallback = (_, __, ___) => true;
    }
    final ch = IOWebSocketChannel.connect(
      wsUrl,
      protocols: const ['xmpp'],
      customClient: io,
    );
    await ch.ready;
    _channel = ch;

    final incoming = StreamController<XmlElement>.broadcast();
    _sub = ch.stream.listen(
      (raw) {
        final text = raw is List<int> ? utf8.decode(raw) : raw as String;
        try {
          incoming.add(XmlDocument.parse(text).rootElement);
        } on XmlException {
          // ignore malformed frames
        }
      },
      onDone: () {
        if (!incoming.isClosed) incoming.close();
        _events.add(const XmppDisconnected('ws done'));
      },
      onError: (e) {
        if (!incoming.isClosed) incoming.close();
        _events.add(XmppDisconnected(e.toString()));
      },
    );

    // <open> → <features>
    ch.sink.add(
      '<open xmlns="urn:ietf:params:xml:ns:xmpp-framing" to="$domain" version="1.0"/>',
    );
    await incoming.stream
        .firstWhere(
          (e) => e.localName == 'features' || e.localName == 'stream:features',
        )
        .timeout(const Duration(seconds: 5));

    // SASL PLAIN
    final payload = base64.encode(
      utf8.encode('\u0000$email\u0000$saslPassword'),
    );
    ch.sink.add(
      '<auth xmlns="urn:ietf:params:xml:ns:xmpp-sasl" mechanism="PLAIN">$payload</auth>',
    );
    final saslResp = await incoming.stream
        .firstWhere((e) => e.localName == 'success' || e.localName == 'failure')
        .timeout(const Duration(seconds: 5));
    if (saslResp.localName != 'success') {
      await ch.sink.close();
      throw StateError('SASL failed: ${saslResp.toXmlString()}');
    }

    // <open> restart → <features>
    ch.sink.add(
      '<open xmlns="urn:ietf:params:xml:ns:xmpp-framing" to="$domain" version="1.0"/>',
    );
    await incoming.stream
        .firstWhere(
          (e) => e.localName == 'features' || e.localName == 'stream:features',
        )
        .timeout(const Duration(seconds: 5));

    // Bind
    ch.sink.add(
      '<iq type="set" id="bind1"><bind xmlns="urn:ietf:params:xml:ns:xmpp-bind">'
      '<resource>$resource</resource></bind></iq>',
    );
    final bindResp = await incoming.stream
        .firstWhere(
          (e) => e.localName == 'iq' && e.getAttribute('type') == 'result',
        )
        .timeout(const Duration(seconds: 5));
    _fullJid = bindResp.findAllElements('jid').first.innerText;

    // Kick off routing loop on subsequent stanzas.
    incoming.stream.listen(_routeStanza);

    // Initial presence — triggers server-side roster presence probe reply.
    ch.sink.add('<presence/>');

    _events.add(XmppConnected(_fullJid));
  }

  void _routeStanza(XmlElement el) {
    switch (el.localName) {
      case 'message':
        _handleMessage(el);
      case 'presence':
        _handlePresence(el);
    }
  }

  void _handleMessage(XmlElement el) {
    final body = el.getElement('body')?.innerText;
    if (body == null) return;
    final from = el.getAttribute('from') ?? '';
    final to = el.getAttribute('to') ?? '';
    final id = el.getAttribute('id') ?? '';
    final type = el.getAttribute('type');
    _events.add(
      XmppChatMessage(
        from: from,
        to: to,
        body: body,
        stanzaId: id,
        isGroupChat: type == 'groupchat',
      ),
    );
  }

  void _handlePresence(XmlElement el) {
    final from = el.getAttribute('from') ?? '';
    final bare = from.contains('/')
        ? from.substring(0, from.indexOf('/'))
        : from;
    final type = el.getAttribute('type');
    final show = type == 'unavailable'
        ? 'offline'
        : (el.getElement('show')?.innerText ?? 'online');
    final status = el.getElement('status')?.innerText;
    _events.add(XmppPresenceUpdate(fromBare: bare, show: show, status: status));
  }

  void sendChat({required String toBareJid, required String body, String? id}) {
    final stanzaId =
        id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    _channel?.sink.add(
      '<message id="$stanzaId" to="$toBareJid" type="chat">'
      '<body>${_esc(body)}</body></message>',
    );
  }

  void sendGroupChat({
    required String roomJid,
    required String body,
    String? id,
  }) {
    final stanzaId =
        id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    _channel?.sink.add(
      '<message id="$stanzaId" to="$roomJid" type="groupchat">'
      '<body>${_esc(body)}</body></message>',
    );
  }

  void joinMuc(String roomJid, String nick) {
    _channel?.sink.add('<presence to="$roomJid/$nick"/>');
  }

  Future<void> disconnect() async {
    try {
      _channel?.sink.add(
        '<close xmlns="urn:ietf:params:xml:ns:xmpp-framing"/>',
      );
      await _sub?.cancel();
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _fullJid = '';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
