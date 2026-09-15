import 'dart:async';

import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import '../../rainbow/xmpp_client.dart';
import '../outgoing_queue.dart';
import 'auth_state_capsule.dart';
import 'config_capsule.dart';
import 'messages_capsule.dart';
import 'outgoing_queue_capsule.dart';
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
    required this.updateBubble,
    required this.deleteBubble,
    required this.inviteToBubble,
    required this.acceptBubbleInvitation,
    required this.declineBubbleInvitation,
    required this.leaveBubble,
    required this.sendChatState,
    required this.sendPeerFile,
    required this.sendGroupFile,
    required this.reactToPeer,
    required this.reactToGroup,
    required this.editPeer,
    required this.editGroup,
    required this.retractPeer,
    required this.retractGroup,
    required this.moderateGroup,
    required this.loadOlder,
  });

  final void Function(RainbowUser peer, String body, {String? replyToStanzaId})
  sendPeer;
  final void Function(
    RainbowBubble bubble,
    String body, {
    String? replyToStanzaId,
    String? thread,
    String? subject,
  })
  sendGroup;
  final void Function(RainbowBubble bubble) joinMuc;
  final Future<void> Function(String show, {String? status}) setMyPresence;
  final Future<RainbowBubble> Function(String name, {String? topic})
  createBubble;
  final Future<RainbowBubble> Function(
    RainbowBubble bubble, {
    String? name,
    String? topic,
  })
  updateBubble;
  final Future<void> Function(RainbowBubble bubble) deleteBubble;
  final Future<RainbowBubble> Function(
    RainbowBubble bubble, {
    String? userId,
    String? loginEmail,
  })
  inviteToBubble;
  final Future<RainbowBubble> Function(RainbowBubble bubble)
  acceptBubbleInvitation;
  final Future<RainbowBubble> Function(RainbowBubble bubble)
  declineBubbleInvitation;
  final Future<RainbowBubble> Function(RainbowBubble bubble) leaveBubble;
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
  final void Function(RainbowUser peer, {required String targetStanzaId})
  retractPeer;
  final void Function(RainbowBubble bubble, {required String targetStanzaId})
  retractGroup;
  final void Function(
    RainbowBubble bubble, {
    required String targetStanzaId,
    String? reason,
  })
  moderateGroup;

  /// Fires a XEP-0313 `<before>` anchored MAM query for older messages
  /// on `threadKey`. Returns `true` if a request was dispatched.
  final bool Function(String threadKey) loadOlder;
}

ChatActions chatActionsCapsule(CapsuleHandle use) {
  final config = use(configCapsule);
  final rest = use(restCapsule);
  final xmpp = use(xmppCapsule);
  final auth = use(authCapsule);
  final outbox = use(outgoingQueueCapsule);

  String peerThreadKey(RainbowUser peer) => '${peer.id}@${config.xmppDomain}';
  String bubbleThreadKey(RainbowBubble b) => '${b.id}@muc.${config.xmppDomain}';

  // Drain the persistent outbox on every XmppConnected — a fresh
  // sign-in or a reconnect after a network gap both replay queued
  // sends in FIFO order.
  use.effect(() {
    final sub = xmpp.events.where((e) => e is XmppConnected).listen((_) async {
      final me = auth.me;
      if (me == null) return;
      final queued = await outbox.readAll(me.id);
      for (final q in queued) {
        try {
          if (q.isGroupChat) {
            xmpp.sendGroupChat(
              roomJid: q.threadKey,
              body: q.body,
              id: q.id,
              replyToStanzaId: q.replyToStanzaId,
            );
          } else {
            xmpp.sendChat(
              toBareJid: q.threadKey,
              body: q.body,
              id: q.id,
              replyToStanzaId: q.replyToStanzaId,
            );
          }
          await outbox.remove(me.id, q.id);
        } on Object {
          // Leave the entry queued; next XmppConnected will retry.
          break;
        }
      }
    });
    return sub.cancel;
  }, [xmpp, auth.me?.id]);

  void sendPeer(RainbowUser peer, String body, {String? replyToStanzaId}) {
    final key = peerThreadKey(peer);
    final stanzaId = _newStanzaId();
    xmpp.sendChat(
      toBareJid: key,
      body: body,
      id: stanzaId,
      replyToStanzaId: replyToStanzaId,
    );
    if (!xmpp.isConnected && auth.me != null) {
      // Belt-and-braces persistence: queue for replay on the next
      // XmppConnected. xmpp.sendChat above was a no-op because the
      // socket was null.
      unawaited(
        outbox.add(
          auth.me!.id,
          QueuedSend(
            id: stanzaId,
            threadKey: key,
            isGroupChat: false,
            body: body,
            queuedAt: DateTime.now(),
            replyToStanzaId: replyToStanzaId,
          ),
        ),
      );
    }
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
        pendingAck: true,
      ),
    );
  }

  void sendGroup(
    RainbowBubble bubble,
    String body, {
    String? replyToStanzaId,
    String? thread,
    String? subject,
  }) {
    final key = bubbleThreadKey(bubble);
    final stanzaId = _newStanzaId();
    xmpp.sendGroupChat(
      roomJid: key,
      body: body,
      id: stanzaId,
      replyToStanzaId: replyToStanzaId,
      thread: thread,
      subject: subject,
    );
    if (!xmpp.isConnected && auth.me != null) {
      unawaited(
        outbox.add(
          auth.me!.id,
          QueuedSend(
            id: stanzaId,
            threadKey: key,
            isGroupChat: true,
            body: body,
            queuedAt: DateTime.now(),
            replyToStanzaId: replyToStanzaId,
          ),
        ),
      );
    }
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
        thread: thread,
        subject: subject,
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

  Future<RainbowBubble> updateBubble(
    RainbowBubble bubble, {
    String? name,
    String? topic,
  }) => rest.updateRoom(bubble.id, name: name, topic: topic);

  Future<void> deleteBubble(RainbowBubble bubble) => rest.deleteRoom(bubble.id);

  Future<RainbowBubble> inviteToBubble(
    RainbowBubble bubble, {
    String? userId,
    String? loginEmail,
  }) => rest.inviteToRoom(bubble.id, userId: userId, loginEmail: loginEmail);

  Future<RainbowBubble> _setMyStatus(RainbowBubble bubble, String status) {
    final myId = auth.me?.id;
    if (myId == null) {
      throw StateError('No signed-in user to set bubble status for.');
    }
    return rest.setRoomMemberStatus(
      bubbleId: bubble.id,
      userId: myId,
      status: status,
    );
  }

  Future<RainbowBubble> acceptBubbleInvitation(RainbowBubble bubble) =>
      _setMyStatus(bubble, 'accepted');

  Future<RainbowBubble> declineBubbleInvitation(RainbowBubble bubble) =>
      _setMyStatus(bubble, 'declined');

  Future<RainbowBubble> leaveBubble(RainbowBubble bubble) =>
      _setMyStatus(bubble, 'declined');

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

  void retractPeer(RainbowUser peer, {required String targetStanzaId}) {
    final key = peerThreadKey(peer);
    xmpp.sendRetract(toBareJid: key, targetStanzaId: targetStanzaId);
    applyRetractLocally(threadKey: key, targetStanzaId: targetStanzaId);
  }

  void retractGroup(RainbowBubble bubble, {required String targetStanzaId}) {
    final key = bubbleThreadKey(bubble);
    xmpp.sendRetract(
      toBareJid: key,
      targetStanzaId: targetStanzaId,
      isGroupChat: true,
    );
    applyRetractLocally(threadKey: key, targetStanzaId: targetStanzaId);
  }

  // XEP-0425 moderation — owner/moderator removes another member's MUC
  // message. The stub fans the tombstone back to us, so no local apply.
  void moderateGroup(
    RainbowBubble bubble, {
    required String targetStanzaId,
    String? reason,
  }) {
    xmpp.sendModeration(
      roomBareJid: bubbleThreadKey(bubble),
      targetStanzaId: targetStanzaId,
      reason: reason,
    );
  }

  return ChatActions(
    sendPeer: sendPeer,
    sendGroup: sendGroup,
    joinMuc: joinMuc,
    setMyPresence: setMyPresence,
    createBubble: createBubble,
    updateBubble: updateBubble,
    deleteBubble: deleteBubble,
    inviteToBubble: inviteToBubble,
    acceptBubbleInvitation: acceptBubbleInvitation,
    declineBubbleInvitation: declineBubbleInvitation,
    leaveBubble: leaveBubble,
    sendChatState: sendChatState,
    sendPeerFile: sendPeerFile,
    sendGroupFile: sendGroupFile,
    reactToPeer: reactToPeer,
    reactToGroup: reactToGroup,
    editPeer: editPeer,
    editGroup: editGroup,
    retractPeer: retractPeer,
    retractGroup: retractGroup,
    moderateGroup: moderateGroup,
    loadOlder: (threadKey) => loadOlderMessages(xmpp, threadKey),
  );
}

String _newStanzaId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(16);
