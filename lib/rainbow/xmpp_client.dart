import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xml/xml.dart';

import '_xmpp_socket.dart';

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

/// RFC 6120 §4.9 stream-level error (`<stream:error>`). Fatal — the
/// stream is closing. [condition] is the defined-condition local name
/// (e.g. `not-authorized`, `policy-violation`), [text] the optional
/// human-readable description.
class XmppStreamError extends XmppEvent {
  const XmppStreamError({required this.condition, this.text});
  final String condition;
  final String? text;
}

/// RFC 6120 §8.3 stanza-level error — an `iq`/`message`/`presence`
/// stanza with `type="error"`. Surfaced so callers learn when an
/// operation failed instead of the error being silently dropped.
class XmppStanzaError extends XmppEvent {
  const XmppStanzaError({
    required this.kind,
    required this.from,
    required this.id,
    required this.condition,
    this.errorType,
    this.text,
  });

  /// 'iq' | 'message' | 'presence'.
  final String kind;
  final String from;
  final String id;

  /// RFC 6120 §8.3.2 error type: auth | cancel | modify | wait.
  final String? errorType;

  /// Defined-condition local name (e.g. `service-unavailable`).
  final String condition;
  final String? text;
}

/// Thrown by [RainbowXmppClient.sendIq] when the peer answers an IQ with
/// `type="error"`. Mirrors RFC 6120 §8.3 error structure.
class XmppIqError implements Exception {
  XmppIqError({required this.condition, this.type, this.text});

  factory XmppIqError.from(XmlElement iq) {
    final err = iq.getElement('error');
    var condition = 'undefined-condition';
    String? text;
    String? type;
    if (err != null) {
      type = err.getAttribute('type');
      for (final c in err.childElements) {
        if (c.localName == 'text') {
          text = c.innerText;
        } else {
          condition = c.localName;
        }
      }
    }
    return XmppIqError(condition: condition, type: type, text: text);
  }

  final String condition;

  /// RFC 6120 §8.3.2 error type: auth | cancel | modify | wait.
  final String? type;
  final String? text;

  @override
  String toString() =>
      'XmppIqError($type/$condition${text != null ? ': $text' : ''})';
}

/// Internal bookkeeping for an in-flight [RainbowXmppClient.sendIq].
class _PendingIq {
  _PendingIq(this.completer, this.timer);
  final Completer<XmlElement> completer;
  final Timer timer;
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
    this.thread,
    this.subject,
  });
  final String from;
  final String to;
  final String body;
  final String stanzaId;
  final bool isGroupChat;
  final XmppAttachment? attachment;
  final String? replyToStanzaId;

  /// XEP-0201 thread id — the group topic this message belongs to.
  final String? thread;

  /// Topic title carried on the message that opens a topic.
  final String? subject;
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
    this.thread,
    this.subject,
  });
  final String from;
  final String to;
  final String body;
  final String stanzaId;
  final DateTime sentAt;
  final bool isGroupChat;
  final XmppAttachment? attachment;
  final String? replyToStanzaId;
  final String? thread;
  final String? subject;
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

/// XEP-0045 MUC occupant presence — someone joined or left a room (or the
/// room reflected our own join). [available] is false on `unavailable`.
class XmppMucOccupant extends XmppEvent {
  const XmppMucOccupant({
    required this.roomBareJid,
    required this.nick,
    required this.available,
    this.realJid,
    this.affiliation = 'none',
    this.role = 'participant',
  });
  final String roomBareJid;
  final String nick;
  final bool available;
  final String? realJid;
  final String affiliation;
  final String role;
}

/// RFC 6121 §3 inbound presence subscription stanza — one of
/// `subscribe` / `subscribed` / `unsubscribe` / `unsubscribed`. UI can
/// prompt to approve/deny an inbound `subscribe`, or refresh the roster
/// on `subscribed` / `unsubscribed`.
class XmppSubscription extends XmppEvent {
  const XmppSubscription({required this.fromBare, required this.type});
  final String fromBare;

  /// subscribe | subscribed | unsubscribe | unsubscribed.
  final String type;
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

/// XEP-0425 moderation tombstone — a MUC moderator removed the target
/// message. Rendered as a "removed by a moderator" placeholder.
class XmppModeration extends XmppEvent {
  const XmppModeration({
    required this.fromBare,
    required this.targetStanzaId,
    required this.byBare,
    required this.reason,
    required this.isGroupChat,
  });
  final String fromBare;
  final String targetStanzaId;
  final String byBare;
  final String? reason;
  final bool isGroupChat;
}

/// Server-issued sent-ack — the corresponding local echo can transition
/// from `MessageStatus.sending` to `sent`.
class XmppSentAck extends XmppEvent {
  const XmppSentAck({required this.stanzaId});
  final String stanzaId;
}

/// End of a XEP-0313 MAM page — carries the RSM window bounds so
/// callers can drive "load older" pagination without buffering the
/// entire archive up-front.
class XmppMamFin extends XmppEvent {
  const XmppMamFin({
    required this.queryId,
    required this.complete,
    required this.first,
    required this.last,
    required this.count,
  });
  final String queryId;
  final bool complete;
  final String first;
  final String last;
  final int count;
}

/// XEP-0166 Jingle signaling event. The [jingleXml] is the raw
/// `<jingle .../>` element serialised as XML so the call layer can
/// deserialise the `<content>`, `<description>`, and `<transport>`
/// children without this parser needing to know about SDP.
class XmppJingle extends XmppEvent {
  const XmppJingle({
    required this.fromFullJid,
    required this.iqId,
    required this.sid,
    required this.action,
    required this.jingleXml,
  });
  final String fromFullJid;
  final String iqId;
  final String sid;
  final String action;
  final String jingleXml;
}

/// MUC-scoped group-call marker (`<call xmlns="urn:rainbow:muc-call:1"
/// state="started|ended" sid="…"/>`) broadcast in a bubble by the
/// initiator so late-joining members see a "Join call" chip.
class XmppMucCallMarker extends XmppEvent {
  const XmppMucCallMarker({
    required this.roomBareJid,
    required this.fromResource,
    required this.state,
    required this.sid,
  });
  final String roomBareJid;
  final String fromResource;
  final String state;
  final String sid;
}

/// Server-initiated roster push (`<iq type="set"><query
/// xmlns="jabber:iq:roster"><item .../></query></iq>`). The XMPP
/// client emits one of these per `<item/>` element so higher-level
/// state (e.g. the roster capsule) can refresh in-place.
class XmppRosterPush extends XmppEvent {
  const XmppRosterPush({
    required this.peerBareJid,
    required this.name,
    required this.subscription,
  });
  final String peerBareJid;
  final String name;
  final String subscription;

  bool get isRemove => subscription == 'remove';
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
  // For resumable sessions [_outbound] retains the raw text of every
  // counted stanza so a later `<resume/>` can retransmit whatever the
  // server acknowledges it never saw.
  static const _smNs = 'urn:xmpp:sm:3';
  bool _smEnabled = false;
  bool _smResumable = false;
  String _smid = '';
  int _hOut = 0;
  int _hIn = 0;
  final _pendingAcks = <int, String>{};
  final _outbound = <int, String>{};

  // RFC 6120 §8.2.3 outstanding request/response IQs keyed by id.
  final _pendingIqs = <String, _PendingIq>{};

  /// True when the last `<enabled/>` announced `resume="true"` and a
  /// non-empty [_smid] — i.e. a subsequent [resume] call is meaningful.
  bool get canResume => _smResumable && _smid.isNotEmpty;

  /// Write [stanza] to the socket, counting it for XEP-0198 if SM is on.
  void _send(String stanza) {
    if (_smEnabled) {
      _hOut++;
      if (_smResumable) _outbound[_hOut] = stanza;
    }
    _channel?.sink.add(stanza);
  }

  // Testing hooks: enable the SM state machine without a real WebSocket
  // handshake and inject inbound stanzas to drive `_routeStanza`.
  @visibleForTesting
  void debugEnableSm() => _smEnabled = true;
  @visibleForTesting
  void debugEnableSmResumable(String smid) {
    _smEnabled = true;
    _smResumable = true;
    _smid = smid;
  }

  @visibleForTesting
  int get debugHOut => _hOut;
  @visibleForTesting
  int get debugHIn => _hIn;
  @visibleForTesting
  int get debugPendingAckCount => _pendingAcks.length;
  @visibleForTesting
  int get debugOutboundCount => _outbound.length;
  @visibleForTesting
  Future<void> debugSimulateDrop() async {
    // Close the channel without emitting `<close/>` or clearing SM
    // state — simulates a raw TCP drop so `resume()` becomes viable.
    try {
      await _sub?.cancel();
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _fullJid = '';
  }

  @visibleForTesting
  void debugRouteStanza(XmlElement el) => _routeStanza(el);

  Future<void> connect({
    required String email,
    required String saslPassword,
    String resource = 'flutter',
  }) async {
    final ch = await openXmppSocket(
      wsUrl,
      acceptSelfSignedCerts: acceptSelfSignedCerts,
    );
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
        _failAllPendingIqs('ws done');
        _events.add(const XmppDisconnected('ws done'));
      },
      onError: (e) {
        if (!incoming.isClosed) incoming.close();
        _failAllPendingIqs(e.toString());
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
    // We ask for `resume="true"` so a later [resume] call can pick up
    // where we left off after a WS drop.
    ch.sink.add('<enable xmlns="$_smNs" resume="true"/>');
    try {
      final smResp = await incoming.stream
          .firstWhere(
            (e) =>
                e.name.namespaceUri == _smNs &&
                (e.localName == 'enabled' || e.localName == 'failed'),
          )
          .timeout(const Duration(seconds: 3));
      if (smResp.localName == 'enabled') {
        _smEnabled = true;
        _smid = smResp.getAttribute('id') ?? '';
        final resumeAttr = smResp.getAttribute('resume') ?? '';
        _smResumable = resumeAttr == 'true' || resumeAttr == '1';
      } else {
        _smEnabled = false;
      }
    } catch (_) {
      _smEnabled = false;
    }

    // Initial presence — triggers server-side roster presence probe reply.
    _send('<presence/>');

    _events.add(XmppConnected(_fullJid));
  }

  /// XEP-0198 §5 stream resumption. Opens a new WS, does SASL, then
  /// sends `<resume previd="…" h="_hIn"/>` instead of a bind. On
  /// `<resumed h="N"/>`, retransmits any queued outbound stanzas with
  /// counter > N and emits [XmppConnected].
  ///
  /// Throws [StateError] if [canResume] is false, or if the server
  /// answers `<failed/>`. Callers should fall back to [connect] in
  /// that case (which discards all prior SM state).
  Future<void> resume({
    required String email,
    required String saslPassword,
  }) async {
    if (!canResume) {
      throw StateError(
        'no resumable session — call connect() for a fresh stream',
      );
    }
    // The previd we're about to send. Cleared eagerly so a failed
    // resume can't be retried against the same (server-reaped) id.
    final previd = _smid;
    final resumedH = _hIn;

    final ch = await openXmppSocket(
      wsUrl,
      acceptSelfSignedCerts: acceptSelfSignedCerts,
    );
    _channel = ch;

    final incoming = StreamController<XmlElement>.broadcast();
    _sub = ch.stream.listen(
      (raw) {
        final text = raw is List<int> ? utf8.decode(raw) : raw as String;
        try {
          incoming.add(XmlDocument.parse(text).rootElement);
        } on XmlException {
          // ignore
        }
      },
      onDone: () {
        if (!incoming.isClosed) incoming.close();
        _failAllPendingIqs('ws done');
        _events.add(const XmppDisconnected('ws done'));
      },
      onError: (e) {
        if (!incoming.isClosed) incoming.close();
        _failAllPendingIqs(e.toString());
        _events.add(XmppDisconnected(e.toString()));
      },
    );

    ch.sink.add(
      '<open xmlns="urn:ietf:params:xml:ns:xmpp-framing" to="$domain" version="1.0"/>',
    );
    await incoming.stream
        .firstWhere(
          (e) => e.localName == 'features' || e.localName == 'stream:features',
        )
        .timeout(const Duration(seconds: 5));

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
      throw StateError('SASL failed on resume: ${saslResp.toXmlString()}');
    }

    ch.sink.add(
      '<open xmlns="urn:ietf:params:xml:ns:xmpp-framing" to="$domain" version="1.0"/>',
    );
    await incoming.stream
        .firstWhere(
          (e) => e.localName == 'features' || e.localName == 'stream:features',
        )
        .timeout(const Duration(seconds: 5));

    ch.sink.add(
      '<resume xmlns="$_smNs" previd="${_esc(previd)}" h="$resumedH"/>',
    );
    final resp = await incoming.stream
        .firstWhere(
          (e) =>
              e.name.namespaceUri == _smNs &&
              (e.localName == 'resumed' || e.localName == 'failed'),
        )
        .timeout(const Duration(seconds: 5));

    if (resp.localName != 'resumed') {
      // Server reaped the parked session (or claimed a different one).
      // Give up SM state so a caller-driven connect() starts clean.
      _smEnabled = false;
      _smResumable = false;
      _smid = '';
      _outbound.clear();
      _pendingAcks.clear();
      throw StateError('resume failed: ${resp.toXmlString()}');
    }

    // Drop retransmit copies the server confirms it saw. Whatever
    // remains in [_outbound] we resend now, preserving order.
    final serverH = int.tryParse(resp.getAttribute('h') ?? '') ?? 0;
    _outbound.removeWhere((k, _) => k <= serverH);
    _pendingAcks.removeWhere((k, _) => k <= serverH);
    final resend = _outbound.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    // Retransmit does NOT bump _hOut — those slots already counted.
    for (final e in resend) {
      _channel?.sink.add(e.value);
    }

    // Route future stanzas.
    incoming.stream.listen(_routeStanza);

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
    // RFC 6120 §4.9 stream error — fatal, not counted by SM.
    if (el.localName == 'error' &&
        el.name.namespaceUri == 'http://etherx.jabber.org/streams') {
      _events.add(_parseStreamError(el));
      return;
    }
    if (_smEnabled) _hIn++;
    final type = el.getAttribute('type');
    // RFC 6120 §8.2.3 — complete a pending sendIq() future by matching id.
    if (el.localName == 'iq' && (type == 'result' || type == 'error')) {
      final pending = _pendingIqs.remove(el.getAttribute('id') ?? '');
      if (pending != null) {
        pending.timer.cancel();
        if (type == 'error') {
          pending.completer.completeError(XmppIqError.from(el));
        } else {
          pending.completer.complete(el);
        }
        return;
      }
    }
    // RFC 6120 §8.3 stanza error — surface instead of dropping.
    if (type == 'error') {
      final kind = el.localName;
      if (kind == 'iq' || kind == 'message' || kind == 'presence') {
        _events.add(_parseStanzaError(kind, el));
        return;
      }
    }
    switch (el.localName) {
      case 'message':
        _handleMessage(el);
      case 'presence':
        _handlePresence(el);
      case 'iq':
        _handleIq(el);
    }
  }

  XmppStreamError _parseStreamError(XmlElement el) {
    var condition = 'undefined-condition';
    String? text;
    for (final c in el.childElements) {
      if (c.localName == 'text') {
        text = c.innerText;
      } else {
        condition = c.localName;
      }
    }
    return XmppStreamError(condition: condition, text: text);
  }

  XmppStanzaError _parseStanzaError(String kind, XmlElement el) {
    final err = el.getElement('error');
    var condition = 'undefined-condition';
    String? text;
    String? errType;
    if (err != null) {
      errType = err.getAttribute('type');
      for (final c in err.childElements) {
        if (c.localName == 'text') {
          text = c.innerText;
        } else {
          condition = c.localName;
        }
      }
    }
    return XmppStanzaError(
      kind: kind,
      from: el.getAttribute('from') ?? '',
      id: el.getAttribute('id') ?? '',
      errorType: errType,
      condition: condition,
      text: text,
    );
  }

  /// RFC 6120 §8.2.3 request/response IQ. Wraps [payload] (the child
  /// element XML) in an `<iq>` with a generated id and completes when a
  /// matching result/error arrives on the routing loop. Throws
  /// [XmppIqError] on an error response, or [TimeoutException] if no
  /// reply lands within [timeout]. Only usable after `connect()`/
  /// `resume()` has started routing (the login handshake awaits inline).
  Future<XmlElement> sendIq({
    required String type,
    String payload = '',
    String? to,
    String? id,
    Duration timeout = const Duration(seconds: 15),
  }) {
    final iqId =
        id ?? 'iq-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final completer = Completer<XmlElement>();
    final timer = Timer(timeout, () {
      if (_pendingIqs.remove(iqId) != null && !completer.isCompleted) {
        completer.completeError(
          TimeoutException('iq $iqId timed out', timeout),
        );
      }
    });
    _pendingIqs[iqId] = _PendingIq(completer, timer);
    final toAttr = to != null ? ' to="${_esc(to)}"' : '';
    _send('<iq type="${_esc(type)}" id="$iqId"$toAttr>$payload</iq>');
    return completer.future;
  }

  /// XEP-0199 ping. Resolves when the server (or [to], if given) answers.
  Future<void> ping({String? to}) =>
      sendIq(type: 'get', payload: '<ping xmlns="urn:xmpp:ping"/>', to: to);

  /// XEP-0012 Last Activity — seconds since [bareJid] was last online
  /// (0 if currently online). Returns null if the query fails/times out.
  Future<Duration?> queryLastActivity(String bareJid) async {
    try {
      final resp = await sendIq(
        type: 'get',
        to: bareJid,
        payload: '<query xmlns="jabber:iq:last"/>',
        timeout: const Duration(seconds: 8),
      );
      final secs = int.tryParse(
        resp.getElement('query')?.getAttribute('seconds') ?? '',
      );
      return secs == null ? null : Duration(seconds: secs);
    } on Object {
      return null;
    }
  }

  void _failAllPendingIqs(String reason) {
    if (_pendingIqs.isEmpty) return;
    final pending = _pendingIqs.values.toList();
    _pendingIqs.clear();
    for (final p in pending) {
      p.timer.cancel();
      if (!p.completer.isCompleted) {
        p.completer.completeError(StateError('iq aborted: $reason'));
      }
    }
  }

  void _handleIq(XmlElement el) {
    // MAM <fin/> and Jingle are the only iqs that reach the routing
    // loop; everything else (bind, sm enable, roster get) is consumed
    // synchronously during connect() / resume().
    final query = el.getElement('query');
    if (query != null && _hasXmlns(query, 'jabber:iq:roster')) {
      for (final item in query.findElements('item')) {
        final jid = item.getAttribute('jid') ?? '';
        if (jid.isEmpty) continue;
        _events.add(
          XmppRosterPush(
            peerBareJid: _bareOf(jid),
            name: item.getAttribute('name') ?? '',
            subscription: item.getAttribute('subscription') ?? 'both',
          ),
        );
      }
      // XEP-0237: acknowledge the push so the server can drop retransmit copies.
      final id = el.getAttribute('id');
      final from = el.getAttribute('from');
      if (id != null) {
        _channel?.sink.add(
          '<iq type="result" id="$id"${from != null ? ' to="$from"' : ''}/>',
        );
      }
      return;
    }
    final fin = el.getElement('fin');
    if (fin != null && _isMamNamespace(fin)) {
      final set = fin.getElement('set');
      final first = set?.getElement('first')?.innerText ?? '';
      final last = set?.getElement('last')?.innerText ?? '';
      final count =
          int.tryParse(set?.getElement('count')?.innerText ?? '') ?? 0;
      final complete = fin.getAttribute('complete') == 'true';
      _events.add(
        XmppMamFin(
          queryId: el.getAttribute('id') ?? '',
          complete: complete,
          first: first,
          last: last,
          count: count,
        ),
      );
      return;
    }
    final jingle = el.getElement('jingle');
    if (jingle != null && _hasXmlns(jingle, 'urn:xmpp:jingle:1')) {
      _events.add(
        XmppJingle(
          fromFullJid: el.getAttribute('from') ?? '',
          iqId: el.getAttribute('id') ?? '',
          sid: jingle.getAttribute('sid') ?? '',
          action: jingle.getAttribute('action') ?? '',
          jingleXml: jingle.toXmlString(),
        ),
      );
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
    // Drop retransmit copies once the server confirms it saw them.
    _outbound.removeWhere((k, _) => k <= h);
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

    // XEP-0425 moderation tombstone — no body, an `<apply-to
    // xmlns="urn:xmpp:fasten:0" id="target"><moderated
    // xmlns="urn:xmpp:message-moderate:0" by="…"><retract
    // xmlns="urn:xmpp:message-retract:0"/><reason/></moderated></apply-to>`.
    final applyToEl = el.getElement('apply-to');
    if (applyToEl != null && _hasXmlns(applyToEl, 'urn:xmpp:fasten:0')) {
      final moderated = applyToEl.getElement('moderated');
      if (moderated != null &&
          _hasXmlns(moderated, 'urn:xmpp:message-moderate:0')) {
        _events.add(
          XmppModeration(
            fromBare: fromBare,
            targetStanzaId: applyToEl.getAttribute('id') ?? '',
            byBare: moderated.getAttribute('by') ?? '',
            reason: moderated.getElement('reason')?.innerText,
            isGroupChat: el.getAttribute('type') == 'groupchat',
          ),
        );
        return;
      }
    }

    // MUC group-call marker (`<call xmlns="urn:rainbow:muc-call:1"
    // state="started|ended" sid="…"/>`). Broadcast to bubble members
    // whenever anyone starts or ends a group call in the room.
    final callEl = el.getElement('call');
    if (callEl != null && _hasXmlns(callEl, 'urn:rainbow:muc-call:1')) {
      final slashIdx = from.indexOf('/');
      _events.add(
        XmppMucCallMarker(
          roomBareJid: slashIdx == -1 ? from : from.substring(0, slashIdx),
          fromResource: slashIdx == -1 ? '' : from.substring(slashIdx + 1),
          state: callEl.getAttribute('state') ?? '',
          sid: callEl.getAttribute('sid') ?? '',
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
        thread: el.getElement('thread')?.innerText.trim(),
        subject: el.getElement('subject')?.innerText.trim(),
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
      thread: inner.getElement('thread')?.innerText.trim(),
      subject: inner.getElement('subject')?.innerText.trim(),
    );
    _events.add(ev);
  }

  void _handlePresence(XmlElement el) {
    final from = el.getAttribute('from') ?? '';
    final bare = from.contains('/')
        ? from.substring(0, from.indexOf('/'))
        : from;
    final type = el.getAttribute('type');
    // XEP-0045 MUC occupant presence — `from` is room@muc/nick and the
    // stanza carries a muc#user <x>. Tracked separately from roster
    // presence so a room JID never lands in the roster presence map.
    if (from.contains('/')) {
      for (final c in el.childElements) {
        if (c.localName == 'x' &&
            _hasXmlns(c, 'http://jabber.org/protocol/muc#user')) {
          final item = c.getElement('item');
          _events.add(
            XmppMucOccupant(
              roomBareJid: bare,
              nick: from.substring(from.indexOf('/') + 1),
              available: type != 'unavailable',
              realJid: item?.getAttribute('jid'),
              affiliation: item?.getAttribute('affiliation') ?? 'none',
              role: item?.getAttribute('role') ?? 'participant',
            ),
          );
          return;
        }
      }
    }
    // RFC 6121 §3 subscription stanzas surface as a distinct event.
    if (type == 'subscribe' ||
        type == 'subscribed' ||
        type == 'unsubscribe' ||
        type == 'unsubscribed') {
      _events.add(XmppSubscription(fromBare: bare, type: type!));
      return;
    }
    final show = type == 'unavailable'
        ? 'offline'
        : (el.getElement('show')?.innerText ?? 'online');
    final status = el.getElement('status')?.innerText;
    _events.add(XmppPresenceUpdate(fromBare: bare, show: show, status: status));
  }

  /// RFC 6121 §3.1 — request a subscription to [bareJid]'s presence.
  void subscribePresence(String bareJid) =>
      _send('<presence to="${_esc(bareJid)}" type="subscribe"/>');

  /// Approve an inbound subscription request from [bareJid] (§3.1.4).
  void approveSubscription(String bareJid) =>
      _send('<presence to="${_esc(bareJid)}" type="subscribed"/>');

  /// Deny/cancel a subscription from [bareJid] (§3.2).
  void denySubscription(String bareJid) =>
      _send('<presence to="${_esc(bareJid)}" type="unsubscribed"/>');

  /// Cancel our own subscription to [bareJid] (§3.3).
  void unsubscribePresence(String bareJid) =>
      _send('<presence to="${_esc(bareJid)}" type="unsubscribe"/>');

  /// XEP/RFC presence probe — ask the server for [bareJid]'s presence.
  void probePresence(String bareJid) =>
      _send('<presence to="${_esc(bareJid)}" type="probe"/>');

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
    String? thread,
    String? subject,
  }) {
    final stanzaId =
        id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final threadXml = (thread != null && thread.isNotEmpty)
        ? '<thread>${_esc(thread)}</thread>'
        : '';
    final subjectXml = (subject != null && subject.isNotEmpty)
        ? '<subject>${_esc(subject)}</subject>'
        : '';
    _send(
      '<message id="$stanzaId" to="$roomJid" type="groupchat">'
      '<body>${_esc(body)}</body>'
      '$threadXml$subjectXml'
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

  /// XEP-0425 moderation — a room moderator retracts another member's
  /// message [targetStanzaId] in the MUC [roomBareJid]. The server
  /// enforces owner/moderator privilege and fans out a `<moderated>`
  /// tombstone (including back to us).
  void sendModeration({
    required String roomBareJid,
    required String targetStanzaId,
    String? reason,
  }) {
    final reasonXml = (reason != null && reason.isNotEmpty)
        ? '<reason>${_esc(reason)}</reason>'
        : '';
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    _send(
      '<iq type="set" id="$id" to="${_esc(roomBareJid)}">'
      '<apply-to xmlns="urn:xmpp:fasten:0" id="${_esc(targetStanzaId)}">'
      '<moderate xmlns="urn:xmpp:message-moderate:0">'
      '<retract xmlns="urn:xmpp:message-retract:0"/>'
      '$reasonXml'
      '</moderate></apply-to></iq>',
    );
  }

  /// Announces a group-call state change in a MUC room. The message
  /// travels as a body-less MUC broadcast so every accepted member
  /// receives the marker via the router's normal fan-out.
  void sendMucCallMarker({
    required String roomBareJid,
    required String state,
    required String sid,
  }) {
    _send(
      '<message to="${_esc(roomBareJid)}" type="groupchat">'
      '<call xmlns="urn:rainbow:muc-call:1"'
      ' state="${_esc(state)}"'
      ' sid="${_esc(sid)}"/>'
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

  /// XEP-0313 MAM query for 1:1 history with [peerBareJid] (or a MUC
  /// room bare JID for group history). Pass [beforeStanzaId] to fetch
  /// the previous page relative to a known cursor. Returns the query
  /// id so the caller can pair the [XmppMamFin] that eventually
  /// terminates the page.
  String queryMamWith(
    String peerBareJid, {
    int max = 50,
    String? beforeStanzaId,
  }) {
    final qid = 'mam-${DateTime.now().microsecondsSinceEpoch}';
    final beforeEl = (beforeStanzaId == null || beforeStanzaId.isEmpty)
        ? ''
        : '<before>${_esc(beforeStanzaId)}</before>';
    _send(
      '<iq type="set" id="$qid">'
      '<query xmlns="urn:xmpp:mam:2" queryid="$qid">'
      '<x xmlns="jabber:x:data" type="submit">'
      '<field var="FORM_TYPE" type="hidden">'
      '<value>urn:xmpp:mam:2</value>'
      '</field>'
      '<field var="with"><value>${_esc(peerBareJid)}</value></field>'
      '</x>'
      '<set xmlns="http://jabber.org/protocol/rsm"><max>$max</max>$beforeEl</set>'
      '</query></iq>',
    );
    return qid;
  }

  /// XEP-0313 MAM query with no `with` field — returns the last [max]
  /// 1:1 archived stanzas across all peers. Used by the Recent tab to
  /// hydrate on sign-in so past conversations survive a sign-out.
  String queryMamAll({int max = 50}) {
    final qid = 'mam-${DateTime.now().microsecondsSinceEpoch}';
    _send(
      '<iq type="set" id="$qid">'
      '<query xmlns="urn:xmpp:mam:2" queryid="$qid">'
      '<x xmlns="jabber:x:data" type="submit">'
      '<field var="FORM_TYPE" type="hidden">'
      '<value>urn:xmpp:mam:2</value>'
      '</field>'
      '</x>'
      '<set xmlns="http://jabber.org/protocol/rsm"><max>$max</max></set>'
      '</query></iq>',
    );
    return qid;
  }

  /// XEP-0166 Jingle session signaling. [toFullJid] is the peer's
  /// full JID (Jingle is per-resource — the stub routes on local-part,
  /// but a real server pins on resource). [contentXml] is the caller-
  /// prepared payload — for `session-initiate` that's the `<content>`
  /// element with a `<description>` + `<transport>`; for
  /// `transport-info` it's typically a single candidate.
  ///
  /// Returns the iq id so the caller can await the ack (currently the
  /// stub replies with an empty `<iq type="result"/>` immediately).
  String sendJingle({
    required String toFullJid,
    required String action,
    required String sid,
    required String contentXml,
    String? initiator,
    String? responder,
  }) {
    final iqId = 'jingle-${DateTime.now().microsecondsSinceEpoch}';
    final initAttr = initiator == null ? '' : ' initiator="${_esc(initiator)}"';
    final respAttr = responder == null ? '' : ' responder="${_esc(responder)}"';
    _send(
      '<iq type="set" id="$iqId" to="${_esc(toFullJid)}">'
      '<jingle xmlns="urn:xmpp:jingle:1" action="${_esc(action)}"'
      ' sid="${_esc(sid)}"$initAttr$respAttr>'
      '$contentXml'
      '</jingle></iq>',
    );
    return iqId;
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
    // Graceful shutdown discards SM state; a subsequent [resume] would
    // be pointless because the server-side parked session is now
    // orphaned (still there until it times out but we no longer hold
    // the previd). Callers who want to survive a drop should NOT call
    // disconnect() — just let the WebSocket break.
    _smEnabled = false;
    _smResumable = false;
    _smid = '';
    _outbound.clear();
    _pendingAcks.clear();
    _hOut = 0;
    _hIn = 0;
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
