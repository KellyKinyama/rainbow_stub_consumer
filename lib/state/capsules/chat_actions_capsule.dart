import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import '../../rainbow/xmpp_client.dart';
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
    required this.sendChatState,
    required this.sendPeerFile,
    required this.sendGroupFile,
    required this.reactToPeer,
    required this.reactToGroup,
    required this.editPeer,
    required this.editGroup,
  });

  final void Function(RainbowUser peer, String body, {String? replyToStanzaId})
  sendPeer;
  final void Function(
    RainbowBubble bubble,
    String body, {
    String? replyToStanzaId,
  })
  sendGroup;
  final void Function(RainbowBubble bubble) joinMuc;
  final Future<void> Function(String show, {String? status}) setMyPresence;
  final Future<RainbowBubble> Function(String name, {String? topic})
  createBubble;
  final void Function(RainbowUser peer, String state) sendChatState;
  final Future<void> Function(
    RainbowUser peer, {
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  })
  sendPeerFile;
  final Future<void> Function(
    RainbowBubble bubble, {
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  })
  sendGroupFile;
  final void Function(
    RainbowUser peer, {
    required String targetStanzaId,
    required List<String> emojis,
  })
  reactToPeer;
  final void Function(
    RainbowBubble bubble, {
    required String targetStanzaId,
    required List<String> emojis,
  })
  reactToGroup;
  final void Function(
    RainbowUser peer, {
    required String originalStanzaId,
    required String newBody,
  })
  editPeer;
  final void Function(
    RainbowBubble bubble, {
    required String originalStanzaId,
    required String newBody,
  })
  editGroup;
}

ChatActions chatActionsCapsule(CapsuleHandle use) {
  final config = use(configCapsule);
  final rest = use(restCapsule);
  final xmpp = use(xmppCapsule);
  final auth = use(authCapsule);

  String peerThreadKey(RainbowUser peer) => '${peer.id}@${config.xmppDomain}';
  String bubbleThreadKey(RainbowBubble b) => '${b.id}@muc.${config.xmppDomain}';

  void sendPeer(RainbowUser peer, String body, {String? replyToStanzaId}) {
    final key = peerThreadKey(peer);
    final stanzaId = _newStanzaId();
    xmpp.sendChat(
      toBareJid: key,
      body: body,
      id: stanzaId,
      replyToStanzaId: replyToStanzaId,
    );
    appendLocalMessage(
      key,
      ChatMessage(
        id: stanzaId,
        body: body,
        from: xmpp.fullJid,
        to: key,
        sentAt: DateTime.now(),
        isMine: true,
        replyToStanzaId: replyToStanzaId,
      ),
    );
  }

  void sendGroup(RainbowBubble bubble, String body, {String? replyToStanzaId}) {
    final key = bubbleThreadKey(bubble);
    final stanzaId = _newStanzaId();
    xmpp.sendGroupChat(
      roomJid: key,
      body: body,
      id: stanzaId,
      replyToStanzaId: replyToStanzaId,
    );
    appendLocalMessage(
      key,
      ChatMessage(
        id: stanzaId,
        body: body,
        from: xmpp.fullJid,
        to: key,
        sentAt: DateTime.now(),
        isMine: true,
        replyToStanzaId: replyToStanzaId,
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

  void sendChatState(RainbowUser peer, String state) {
    xmpp.sendChatState(toBareJid: peerThreadKey(peer), state: state);
  }

  Future<void> sendPeerFile(
    RainbowUser peer, {
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final key = peerThreadKey(peer);
    final desc = await rest.uploadFile(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      peerJid: key,
      peerType: 'user',
    );
    final stanzaId = _newStanzaId();
    final attachment = XmppAttachment(
      id: desc.id,
      url: desc.downloadUrl,
      fileName: desc.fileName,
      mimeType: desc.mimeType,
      size: desc.size,
    );
    final body = '[File: ${desc.fileName}]';
    xmpp.sendChat(
      toBareJid: key,
      body: body,
      id: stanzaId,
      attachment: attachment,
    );
    appendLocalMessage(
      key,
      ChatMessage(
        id: stanzaId,
        body: body,
        from: xmpp.fullJid,
        to: key,
        sentAt: DateTime.now(),
        isMine: true,
        attachment: desc,
      ),
    );
  }

  Future<void> sendGroupFile(
    RainbowBubble bubble, {
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final key = bubbleThreadKey(bubble);
    final desc = await rest.uploadFile(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      peerJid: key,
      peerType: 'room',
    );
    final stanzaId = _newStanzaId();
    final attachment = XmppAttachment(
      id: desc.id,
      url: desc.downloadUrl,
      fileName: desc.fileName,
      mimeType: desc.mimeType,
      size: desc.size,
    );
    final body = '[File: ${desc.fileName}]';
    xmpp.sendGroupChat(
      roomJid: key,
      body: body,
      id: stanzaId,
      attachment: attachment,
    );
    appendLocalMessage(
      key,
      ChatMessage(
        id: stanzaId,
        body: body,
        from: xmpp.fullJid,
        to: key,
        sentAt: DateTime.now(),
        isMine: true,
        attachment: desc,
      ),
    );
  }

  void reactToPeer(
    RainbowUser peer, {
    required String targetStanzaId,
    required List<String> emojis,
  }) {
    xmpp.sendReactions(
      toBareJid: peerThreadKey(peer),
      targetStanzaId: targetStanzaId,
      emojis: emojis,
    );
    // Local echo so the sender's own UI shows the reaction instantly.
    final myId = auth.me?.id;
    if (myId != null) {
      applyReactionsLocally(
        threadKey: peerThreadKey(peer),
        targetStanzaId: targetStanzaId,
        fromUserId: myId,
        emojis: emojis,
      );
    }
  }

  void reactToGroup(
    RainbowBubble bubble, {
    required String targetStanzaId,
    required List<String> emojis,
  }) {
    xmpp.sendReactions(
      toBareJid: bubbleThreadKey(bubble),
      targetStanzaId: targetStanzaId,
      emojis: emojis,
      isGroupChat: true,
    );
    final myId = auth.me?.id;
    if (myId != null) {
      applyReactionsLocally(
        threadKey: bubbleThreadKey(bubble),
        targetStanzaId: targetStanzaId,
        fromUserId: myId,
        emojis: emojis,
      );
    }
  }

  void editPeer(
    RainbowUser peer, {
    required String originalStanzaId,
    required String newBody,
  }) {
    final key = peerThreadKey(peer);
    xmpp.sendChatCorrection(
      toBareJid: key,
      originalStanzaId: originalStanzaId,
      newBody: newBody,
    );
    applyEditLocally(
      threadKey: key,
      originalStanzaId: originalStanzaId,
      newBody: newBody,
    );
  }

  void editGroup(
    RainbowBubble bubble, {
    required String originalStanzaId,
    required String newBody,
  }) {
    final key = bubbleThreadKey(bubble);
    xmpp.sendChatCorrection(
      toBareJid: key,
      originalStanzaId: originalStanzaId,
      newBody: newBody,
      isGroupChat: true,
    );
    applyEditLocally(
      threadKey: key,
      originalStanzaId: originalStanzaId,
      newBody: newBody,
    );
  }

  return ChatActions(
    sendPeer: sendPeer,
    sendGroup: sendGroup,
    joinMuc: joinMuc,
    setMyPresence: setMyPresence,
    createBubble: createBubble,
    sendChatState: sendChatState,
    sendPeerFile: sendPeerFile,
    sendGroupFile: sendGroupFile,
    reactToPeer: reactToPeer,
    reactToGroup: reactToGroup,
    editPeer: editPeer,
    editGroup: editGroup,
  );
}

String _newStanzaId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(16);
