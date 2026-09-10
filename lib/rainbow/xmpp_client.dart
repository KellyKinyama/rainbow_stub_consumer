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
    this.attachment,
    this.replyToStanzaId,
  });
  final String from;
  final String to;
  final String body;
  final String stanzaId;
  final bool isGroupChat;
  final XmppAttachment? attachment;
  final String? replyToStanzaId;
}

class XmppMamMessage extends XmppEvent {
  const XmppMamMessage({
    required this.from,
    required this.to,
    required this.body,
    required this.stanzaId,
    required this.sentAt,
    required this.isGroupChat,
    this.attachment,
    this.replyToStanzaId,
  });
  final String from;
  final String to;
  final String body;
  final String stanzaId;
  final DateTime sentAt;
  final bool isGroupChat;
  final XmppAttachment? attachment;
  final String? replyToStanzaId;
}

/// File payload attached to an XMPP message via the `urn:rainbow:file:1`
/// extension. Read from `<file .../>` inline in the stanza.
class XmppAttachment {
  const XmppAttachment({
    required this.id,
    required this.url,
    required this.fileName,
    required this.mimeType,
    required this.size,
  });
  final String id;
  final String url;
  final String fileName;
  final String mimeType;
  final int size;
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

/// XEP-0184 `<received>` or XEP-0333 `<received>` — the sender's message
/// was delivered to the recipient.
class XmppDeliveryReceipt extends XmppEvent {
  const XmppDeliveryReceipt({required this.fromBare, required this.stanzaId});
  final String fromBare;
  final String stanzaId;
}

/// XEP-0333 `<displayed>` — the recipient viewed the message.
class XmppReadMarker extends XmppEvent {
  const XmppReadMarker({required this.fromBare, required this.stanzaId});
  final String fromBare;
  final String stanzaId;
}

/// XEP-0085 chat state: one of composing / paused / active / inactive / gone.
class XmppChatState extends XmppEvent {
  const XmppChatState({required this.fromBare, required this.state});
  final String fromBare;
  final String state;
}

/// XEP-0444 reactions — the SENDER's *full* current reaction set on
/// [targetStanzaId]. Empty [emojis] means "cleared".
class XmppReactions extends XmppEvent {
  const XmppReactions({
    required this.fromBare,
    required this.targetStanzaId,
    required this.emojis,
  });
  final String fromBare;
  final String targetStanzaId;
  final List<String> emojis;
}

/// XEP-0308 last-message correction — [originalStanzaId] should be
/// replaced by a new message with body [newBody]. Carries the
/// correction stanza's own [newStanzaId] so downstream state can dedupe.
class XmppMessageCorrection extends XmppEvent {
  const XmppMessageCorrection({
    required this.fromBare,
    required this.originalStanzaId,
    required this.newBody,
    required this.newStanzaId,
    required this.isGroupChat,
  });
  final String fromBare;
  final String originalStanzaId;
  final String newBody;
  final String newStanzaId;
  final bool isGroupChat;
}

/// XEP-0424 message retraction — the target message should be removed.
class XmppRetract extends XmppEvent {
  const XmppRetract({
    required this.fromBare,
    required this.targetStanzaId,
    required this.isGroupChat,
  });
  final String fromBare;
  final String targetStanzaId;
  final bool isGroupChat;
}

/// Server-issued sent-ack — the corresponding local echo can transition
/// from `MessageStatus.sending` to `sent`.
class XmppSentAck extends XmppEvent {
  const XmppSentAck({required this.stanzaId});
  final String stanzaId;
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

  // XEP-0198 stream management. Once the server has answered <enabled/>
  // we count every outgoing counted stanza in [_hOut] and every inbound
  // counted stanza in [_hIn]. Body-bearing sends also register in
  // [_pendingAcks] so an incoming `<a h="N"/>` can fan out XmppSentAck.
  static const _smNs = 'urn:xmpp:sm:3';
  bool _smEnabled = false;
  int _hOut = 0;
  int _hIn = 0;
  final _pendingAcks = <int, String>{};

  /// Write [stanza] to the socket, counting it for XEP-0198 if SM is on.
  void _send(String stanza) {
    if (_smEnabled) _hOut++;
    _channel?.sink.add(stanza);
  }

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

    // XEP-0198 stream management. Best-effort: if the server doesn't
    // answer <enabled/> within 3s we silently fall back to a plain
    // stream (sender-side "sent" status will simply stay `sending`).
    ch.sink.add('<enable xmlns="$_smNs"/>');
    try {
      final smResp = await incoming.stream
          .firstWhere(
            (e) =>
                e.name.namespaceUri == _smNs &&
                (e.localName == 'enabled' || e.localName == 'failed'),
          )
          .timeout(const Duration(seconds: 3));
      _smEnabled = smResp.localName == 'enabled';
    } catch (_) {
      _smEnabled = false;
    }

    // Initial presence — triggers server-side roster presence probe reply.
    _send('<presence/>');

    _events.add(XmppConnected(_fullJid));
  }

  void _routeStanza(XmlElement el) {
    // XEP-0198 control stanzas are NOT counted.
    if (el.name.namespaceUri == _smNs) {
      switch (el.localName) {
        case 'r':
          _channel?.sink.add('<a xmlns="$_smNs" h="$_hIn"/>');
        case 'a':
          _handleSmAck(el);
      }
      return;
    }
    if (_smEnabled) _hIn++;
    switch (el.localName) {
      case 'message':
        _handleMessage(el);
      case 'presence':
        _handlePresence(el);
    }
  }

  void _handleSmAck(XmlElement el) {
    final h = int.tryParse(el.getAttribute('h') ?? '');
    if (h == null) return;
    final acked = _pendingAcks.keys.where((k) => k <= h).toList();
    for (final k in acked) {
      final id = _pendingAcks.remove(k);
      if (id != null && id.isNotEmpty) {
        _events.add(XmppSentAck(stanzaId: id));
      }
    }
  }

  void _handleMessage(XmlElement el) {
    // MAM (XEP-0313) archived message: unwrap <result>/<forwarded>/<message>
    // and emit as XmppMamMessage so hydration paths can order by sentAt.
    final mamResult = el.getElement('result');
    if (mamResult != null && _isMamNamespace(mamResult)) {
      _handleMamResult(mamResult);
      return;
    }

    final from = el.getAttribute('from') ?? '';
    final fromBare = _bareOf(from);

    // XEP-0184 delivery receipt AND XEP-0333 chat marker `received`.
    for (final child in el.childElements) {
      if (child.localName == 'received' &&
          (_hasXmlns(child, 'urn:xmpp:receipts') ||
              _hasXmlns(child, 'urn:xmpp:chat-markers:0'))) {
        _events.add(
          XmppDeliveryReceipt(
            fromBare: fromBare,
            stanzaId: child.getAttribute('id') ?? '',
          ),
        );
        return;
      }
      if (child.localName == 'displayed' &&
          _hasXmlns(child, 'urn:xmpp:chat-markers:0')) {
        _events.add(
          XmppReadMarker(
            fromBare: fromBare,
            stanzaId: child.getAttribute('id') ?? '',
          ),
        );
        return;
      }
    }

    // XEP-0085 chat state (may or may not come with a body).
    for (final child in el.childElements) {
      if (_hasXmlns(child, 'http://jabber.org/protocol/chatstates')) {
        _events.add(XmppChatState(fromBare: fromBare, state: child.localName));
        break;
      }
    }

    // XEP-0444 reactions — has no body, target is the reactions@id
    // attribute; emojis are inner <reaction>text</reaction> children.
    final reactionsEl = el.getElement('reactions');
    if (reactionsEl != null && _hasXmlns(reactionsEl, 'urn:xmpp:reactions:0')) {
      final targetId = reactionsEl.getAttribute('id') ?? '';
      final emojis = reactionsEl.childElements
          .where((c) => c.localName == 'reaction')
          .map((c) => c.innerText)
          .where((s) => s.isNotEmpty)
          .toList();
      _events.add(
        XmppReactions(
          fromBare: fromBare,
          targetStanzaId: targetId,
          emojis: emojis,
        ),
      );
      return;
    }

    // XEP-0424 message retraction — no body, `<retract id="…"/>`.
    final retractEl = el.getElement('retract');
    if (retractEl != null &&
        _hasXmlns(retractEl, 'urn:xmpp:message-retract:1')) {
      _events.add(
        XmppRetract(
          fromBare: fromBare,
          targetStanzaId: retractEl.getAttribute('id') ?? '',
          isGroupChat: el.getAttribute('type') == 'groupchat',
        ),
      );
      return;
    }

    // Server-issued sent-ack for one of my messages.
    // Historically emitted as `<sent xmlns="urn:xmpp:sent-ack:1"/>`;
    // now derived from XEP-0198 `<a h="N"/>` in `_handleSmAck`. The
    // legacy detection is gone.

    final body = el.getElement('body')?.innerText;
    if (body == null) return;
    final to = el.getAttribute('to') ?? '';
    final id = el.getAttribute('id') ?? '';
    final type = el.getAttribute('type');

    // XEP-0308 message correction — has a body + a <replace id="original"/>
    // sibling. Emit as a correction event and swallow the message so
    // consumers don't render it as a fresh reply.
    final replaceEl = el.getElement('replace');
    if (replaceEl != null &&
        _hasXmlns(replaceEl, 'urn:xmpp:message-correct:0')) {
      _events.add(
        XmppMessageCorrection(
          fromBare: fromBare,
          originalStanzaId: replaceEl.getAttribute('id') ?? '',
          newBody: body,
          newStanzaId: id,
          isGroupChat: type == 'groupchat',
        ),
      );
      return;
    }

    _events.add(
      XmppChatMessage(
        from: from,
        to: to,
        body: body,
        stanzaId: id,
        isGroupChat: type == 'groupchat',
        attachment: _readAttachment(el),
        replyToStanzaId: _readReplyTargetId(el),
      ),
    );
  }

  /// Returns the target stanza id of an XEP-0461 `<reply id="..."/>`
  /// child, or null if no reply reference is present.
  static String? _readReplyTargetId(XmlElement message) {
    for (final child in message.childElements) {
      if (child.localName == 'reply' && _hasXmlns(child, 'urn:xmpp:reply:0')) {
        return child.getAttribute('id');
      }
    }
    return null;
  }

  static XmppAttachment? _readAttachment(XmlElement message) {
    for (final child in message.childElements) {
      if (child.localName == 'file' && _hasXmlns(child, 'urn:rainbow:file:1')) {
        return XmppAttachment(
          id: child.getAttribute('id') ?? '',
          url: child.getAttribute('url') ?? '',
          fileName: child.getAttribute('name') ?? 'file',
          mimeType: child.getAttribute('mime') ?? 'application/octet-stream',
          size: int.tryParse(child.getAttribute('size') ?? '') ?? 0,
        );
      }
    }
    return null;
  }

  static bool _hasXmlns(XmlElement el, String ns) =>
      el.getAttribute('xmlns') == ns || el.name.namespaceUri == ns;

  static String _bareOf(String jid) =>
      jid.contains('/') ? jid.substring(0, jid.indexOf('/')) : jid;

  static bool _isMamNamespace(XmlElement el) {
    const mam = 'urn:xmpp:mam:2';
    return el.getAttribute('xmlns') == mam || el.name.namespaceUri == mam;
  }

  void _handleMamResult(XmlElement result) {
    final forwarded = result.getElement('forwarded');
    if (forwarded == null) return;
    final inner = forwarded.getElement('message');
    if (inner == null) return;
    final body = inner.getElement('body')?.innerText;
    if (body == null) return;
    final delay = forwarded.getElement('delay');
    final stamp = delay?.getAttribute('stamp');
    final sentAt = stamp != null
        ? DateTime.tryParse(stamp) ?? DateTime.now()
        : DateTime.now();
    final ev = XmppMamMessage(
      from: inner.getAttribute('from') ?? '',
      to: inner.getAttribute('to') ?? '',
      body: body,
      stanzaId: inner.getAttribute('id') ?? '',
      sentAt: sentAt,
      isGroupChat: inner.getAttribute('type') == 'groupchat',
      attachment: _readAttachment(inner),
      replyToStanzaId: _readReplyTargetId(inner),
    );
    _events.add(ev);
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

  void sendChat({
    required String toBareJid,
    required String body,
    String? id,
    XmppAttachment? attachment,
    String? replyToStanzaId,
  }) {
    final stanzaId =
        id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    _send(
      '<message id="$stanzaId" to="$toBareJid" type="chat">'
      '<body>${_esc(body)}</body>'
      '${_renderFile(attachment)}'
      '${_renderReply(replyToStanzaId)}'
      '<request xmlns="urn:xmpp:receipts"/>'
      '<markable xmlns="urn:xmpp:chat-markers:0"/>'
      '</message>',
    );
    // XEP-0198: remember which outgoing counter this stanza sat at so
    // that a subsequent `<a h="N"/>` from the server can fan out an
    // XmppSentAck for it. Then solicit an ack now.
    if (_smEnabled) {
      _pendingAcks[_hOut] = stanzaId;
      _channel?.sink.add('<r xmlns="$_smNs"/>');
    }
  }

  void sendGroupChat({
    required String roomJid,
    required String body,
    String? id,
    XmppAttachment? attachment,
    String? replyToStanzaId,
  }) {
    final stanzaId =
        id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    _send(
      '<message id="$stanzaId" to="$roomJid" type="groupchat">'
      '<body>${_esc(body)}</body>'
      '${_renderFile(attachment)}'
      '${_renderReply(replyToStanzaId)}'
      '</message>',
    );
    if (_smEnabled) {
      _pendingAcks[_hOut] = stanzaId;
      _channel?.sink.add('<r xmlns="$_smNs"/>');
    }
  }

  static String _renderFile(XmppAttachment? f) {
    if (f == null) return '';
    return '<file xmlns="urn:rainbow:file:1" '
        'id="${_esc(f.id)}" '
        'url="${_esc(f.url)}" '
        'name="${_esc(f.fileName)}" '
        'mime="${_esc(f.mimeType)}" '
        'size="${f.size}"/>';
  }

  static String _renderReply(String? replyToStanzaId) {
    if (replyToStanzaId == null || replyToStanzaId.isEmpty) return '';
    return '<reply xmlns="urn:xmpp:reply:0" id="${_esc(replyToStanzaId)}"/>';
  }

  void joinMuc(String roomJid, String nick) {
    _send('<presence to="$roomJid/$nick"/>');
  }

  /// XEP-0444 reactions — an idempotent snapshot of the sender's current
  /// reactions on [targetStanzaId]. Pass an empty list to clear.
  void sendReactions({
    required String toBareJid,
    required String targetStanzaId,
    required List<String> emojis,
    bool isGroupChat = false,
  }) {
    final buf = StringBuffer()
      ..write('<message to="${_esc(toBareJid)}"')
      ..write(isGroupChat ? ' type="groupchat">' : ' type="chat">')
      ..write(
        '<reactions xmlns="urn:xmpp:reactions:0" '
        'id="${_esc(targetStanzaId)}">',
      );
    for (final e in emojis) {
      buf.write('<reaction>${_esc(e)}</reaction>');
    }
    buf.write('</reactions></message>');
    _send(buf.toString());
  }

  /// XEP-0308 last-message correction — publishes a NEW stanza that
  /// carries the corrected body and refers to the [originalStanzaId] via
  /// `<replace/>`.
  void sendChatCorrection({
    required String toBareJid,
    required String originalStanzaId,
    required String newBody,
    String? id,
    bool isGroupChat = false,
  }) {
    final stanzaId =
        id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    _send(
      '<message id="$stanzaId" to="${_esc(toBareJid)}"'
      ' type="${isGroupChat ? 'groupchat' : 'chat'}">'
      '<body>${_esc(newBody)}</body>'
      '<replace xmlns="urn:xmpp:message-correct:0"'
      ' id="${_esc(originalStanzaId)}"/>'
      '</message>',
    );
  }

  /// XEP-0424 message retraction — instructs the peer(s) to remove the
  /// message with [targetStanzaId] from their view.
  void sendRetract({
    required String toBareJid,
    required String targetStanzaId,
    bool isGroupChat = false,
  }) {
    _send(
      '<message to="${_esc(toBareJid)}"'
      ' type="${isGroupChat ? 'groupchat' : 'chat'}">'
      '<retract xmlns="urn:xmpp:message-retract:1"'
      ' id="${_esc(targetStanzaId)}"/>'
      '</message>',
    );
  }

  /// XEP-0184 delivery receipt — tells [toBareJid] we received their
  /// message with id [stanzaId].
  void sendDeliveryReceipt({
    required String toBareJid,
    required String stanzaId,
  }) {
    _send(
      '<message to="${_esc(toBareJid)}">'
      '<received xmlns="urn:xmpp:receipts" id="${_esc(stanzaId)}"/>'
      '</message>',
    );
  }

  /// XEP-0333 chat marker — tells [toBareJid] we viewed their message
  /// with id [stanzaId].
  void sendReadMarker({required String toBareJid, required String stanzaId}) {
    _send(
      '<message to="${_esc(toBareJid)}">'
      '<displayed xmlns="urn:xmpp:chat-markers:0" id="${_esc(stanzaId)}"/>'
      '</message>',
    );
  }

  /// XEP-0085 chat state ([state] is composing / paused / active /
  /// inactive / gone).
  void sendChatState({required String toBareJid, required String state}) {
    _send(
      '<message to="${_esc(toBareJid)}" type="chat">'
      '<$state xmlns="http://jabber.org/protocol/chatstates"/>'
      '</message>',
    );
  }

  /// XEP-0313 MAM query for 1:1 history with [peerBareJid].
  void queryMamWith(String peerBareJid, {int max = 50}) {
    final qid = 'mam-${DateTime.now().microsecondsSinceEpoch}';
    _send(
      '<iq type="set" id="$qid">'
      '<query xmlns="urn:xmpp:mam:2" queryid="$qid">'
      '<x xmlns="jabber:x:data" type="submit">'
      '<field var="FORM_TYPE" type="hidden">'
      '<value>urn:xmpp:mam:2</value>'
      '</field>'
      '<field var="with"><value>${_esc(peerBareJid)}</value></field>'
      '</x>'
      '<set xmlns="http://jabber.org/protocol/rsm"><max>$max</max></set>'
      '</query></iq>',
    );
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
