import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../rainbow/models.dart';
import '../rainbow/rest_client.dart';
import '../rainbow/xmpp_client.dart';

/// Root session — owns REST + XMPP; children widgets subscribe via
/// [ChangeNotifier] semantics.
class RainbowSession extends ChangeNotifier {
  RainbowSession(this.config)
    : rest = RainbowRestClient(config),
      xmpp = RainbowXmppClient(wsUrl: config.wsUrl, domain: config.xmppDomain);

  final AppConfig config;
  final RainbowRestClient rest;
  final RainbowXmppClient xmpp;

  RainbowUser? _me;
  RainbowUser? get me => _me;
  bool get isAuthenticated => _me != null;

  final Map<String, RainbowUser> _contactsById = {};
  List<RosterEntry> _roster = const [];
  List<RosterEntry> get roster => _roster;
  RainbowUser? contact(String id) => _contactsById[id];

  List<RainbowBubble> _bubbles = const [];
  List<RainbowBubble> get bubbles => _bubbles;

  /// Live messages per bare-JID conversation (peer or bubble MUC JID).
  final Map<String, List<ChatMessage>> _threads = {};
  List<ChatMessage> thread(String key) =>
      List.unmodifiable(_threads[key] ?? const []);

  StreamSubscription? _xmppSub;

  Future<void> signIn(String email, String password) async {
    final result = await rest.login(email, password);
    _me = result.loggedInUser;
    // Attach XMPP; SASL uses the REST bearer as password (accepted by our stub).
    await xmpp.connect(email: email, saslPassword: result.token);
    _xmppSub = xmpp.events.listen(_onXmppEvent);
    await refreshAll();
    notifyListeners();
  }

  Future<void> signOut() async {
    await _xmppSub?.cancel();
    _xmppSub = null;
    await xmpp.disconnect();
    await rest.logout();
    _me = null;
    _roster = const [];
    _bubbles = const [];
    _contactsById.clear();
    _threads.clear();
    notifyListeners();
  }

  Future<void> refreshAll() async {
    _roster = await rest.networks();
    _contactsById.clear();
    for (final r in _roster) {
      _contactsById[r.peer.id] = r.peer;
    }
    _bubbles = await rest.rooms();
    notifyListeners();
  }

  Future<RainbowBubble> createBubble(String name, {String? topic}) async {
    final b = await rest.createRoom(name, topic: topic);
    _bubbles = [..._bubbles, b];
    notifyListeners();
    return b;
  }

  void sendChatTo(RainbowUser peer, String body) {
    final peerBare = '${peer.id}@${config.xmppDomain}';
    xmpp.sendChat(toBareJid: peerBare, body: body);
    _threads
        .putIfAbsent(peerBare, () => <ChatMessage>[])
        .add(
          ChatMessage(
            id: '${DateTime.now().microsecondsSinceEpoch}',
            body: body,
            from: xmpp.fullJid,
            to: peerBare,
            sentAt: DateTime.now(),
            isMine: true,
          ),
        );
    notifyListeners();
  }

  void sendGroupChatTo(RainbowBubble bubble, String body) {
    final room = '${bubble.id}@muc.${config.xmppDomain}';
    xmpp.sendGroupChat(roomJid: room, body: body);
    _threads
        .putIfAbsent(room, () => <ChatMessage>[])
        .add(
          ChatMessage(
            id: '${DateTime.now().microsecondsSinceEpoch}',
            body: body,
            from: xmpp.fullJid,
            to: room,
            sentAt: DateTime.now(),
            isMine: true,
          ),
        );
    notifyListeners();
  }

  Future<void> setMyPresence(String show, {String? status}) async {
    final id = _me?.id;
    if (id == null) return;
    await rest.setPresence(id, show, status: status);
    notifyListeners();
  }

  void _onXmppEvent(XmppEvent e) {
    if (e is XmppChatMessage) {
      _handleIncomingMessage(e);
    } else if (e is XmppPresenceUpdate) {
      final id = _bareLocal(e.fromBare);
      final c = _contactsById[id];
      if (c != null) {
        _contactsById[id] = RainbowUser(
          id: c.id,
          loginEmail: c.loginEmail,
          firstName: c.firstName,
          lastName: c.lastName,
          displayName: c.displayName,
          jobTitle: c.jobTitle,
          presenceShow: e.show,
          presenceStatus: e.status,
          hasAvatar: c.hasAvatar,
        );
        // Rebuild roster with fresh peer refs.
        _roster = _roster
            .map(
              (r) => r.peer.id == c.id
                  ? RosterEntry(
                      userId: r.userId,
                      peer: _contactsById[c.id]!,
                      status: r.status,
                    )
                  : r,
            )
            .toList();
        notifyListeners();
      }
    } else if (e is XmppConnected) {
      notifyListeners();
    } else if (e is XmppDisconnected) {
      notifyListeners();
    }
  }

  void _handleIncomingMessage(XmppChatMessage e) {
    // Group chat carries the sender-as-nick after the /, and the room JID is
    // the bare part (bubbleId@muc.domain).
    final String key;
    if (e.isGroupChat) {
      key =
          _bareLocal(e.from) == 'muc.${config.xmppDomain}' ||
              e.from.contains('@muc.')
          ? e.from.contains('/')
                ? e.from.substring(0, e.from.indexOf('/'))
                : e.from
          : e.to;
    } else {
      // Direct chat — from is peer's full JID; the conversation is keyed on
      // peer bare JID.
      key = e.from.contains('/')
          ? e.from.substring(0, e.from.indexOf('/'))
          : e.from;
    }
    _threads
        .putIfAbsent(key, () => <ChatMessage>[])
        .add(
          ChatMessage(
            id: e.stanzaId,
            body: e.body,
            from: e.from,
            to: e.to,
            sentAt: DateTime.now(),
            isMine: false,
          ),
        );
    notifyListeners();
  }

  String _bareLocal(String jid) {
    if (jid.contains('/')) jid = jid.substring(0, jid.indexOf('/'));
    if (jid.contains('@')) return jid.substring(0, jid.indexOf('@'));
    return jid;
  }

  @override
  void dispose() {
    _xmppSub?.cancel();
    xmpp.disconnect();
    rest.close();
    super.dispose();
  }
}
