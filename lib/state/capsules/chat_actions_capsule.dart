import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import 'auth_state_capsule.dart';
import 'config_capsule.dart';
import 'messages_capsule.dart';
import 'rest_capsule.dart';
import 'xmpp_capsule.dart';

/// Actions bag: everything the UI needs to mutate live state.
class ChatActions {
  const ChatActions({
    required this.sendPeer,
    required this.sendGroup,
    required this.joinMuc,
    required this.setMyPresence,
    required this.createBubble,
  });

  final void Function(RainbowUser peer, String body) sendPeer;
  final void Function(RainbowBubble bubble, String body) sendGroup;
  final void Function(RainbowBubble bubble) joinMuc;
  final Future<void> Function(String show, {String? status}) setMyPresence;
  final Future<RainbowBubble> Function(String name, {String? topic})
  createBubble;
}

ChatActions chatActionsCapsule(CapsuleHandle use) {
  final config = use(configCapsule);
  final rest = use(restCapsule);
  final xmpp = use(xmppCapsule);
  final auth = use(authCapsule);

  String peerThreadKey(RainbowUser peer) => '${peer.id}@${config.xmppDomain}';
  String bubbleThreadKey(RainbowBubble b) => '${b.id}@muc.${config.xmppDomain}';

  void sendPeer(RainbowUser peer, String body) {
    final key = peerThreadKey(peer);
    final stanzaId = _newStanzaId();
    xmpp.sendChat(toBareJid: key, body: body, id: stanzaId);
    appendLocalMessage(
      key,
      ChatMessage(
        id: stanzaId,
        body: body,
        from: xmpp.fullJid,
        to: key,
        sentAt: DateTime.now(),
        isMine: true,
      ),
    );
  }

  void sendGroup(RainbowBubble bubble, String body) {
    final key = bubbleThreadKey(bubble);
    final stanzaId = _newStanzaId();
    xmpp.sendGroupChat(roomJid: key, body: body, id: stanzaId);
    appendLocalMessage(
      key,
      ChatMessage(
        id: stanzaId,
        body: body,
        from: xmpp.fullJid,
        to: key,
        sentAt: DateTime.now(),
        isMine: true,
      ),
    );
  }

  void joinMuc(RainbowBubble bubble) {
    final key = bubbleThreadKey(bubble);
    final nick = auth.me?.id ?? 'me';
    xmpp.joinMuc(key, nick);
  }

  Future<void> setMyPresence(String show, {String? status}) async {
    final id = auth.me?.id;
    if (id == null) return;
    await rest.setPresence(id, show, status: status);
  }

  Future<RainbowBubble> createBubble(String name, {String? topic}) =>
      rest.createRoom(name, topic: topic);

  return ChatActions(
    sendPeer: sendPeer,
    sendGroup: sendGroup,
    joinMuc: joinMuc,
    setMyPresence: setMyPresence,
    createBubble: createBubble,
  );
}

String _newStanzaId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(16);
