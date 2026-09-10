import 'dart:async';

import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import '../../rainbow/xmpp_client.dart';
import 'auth_state_capsule.dart';
import 'xmpp_capsule.dart';

/// Bare-JID of the peer or bubble whose thread we want to watch. For MUC
/// chats this is the bubble's room JID (e.g. `room-xyz@muc.localhost`);
/// for 1:1 chats it's the peer's bare JID.
typedef ThreadKey = String;

final Map<ThreadKey, Capsule<List<ChatMessage>>> _messagesCache = {};
final Map<ThreadKey, Capsule<InMemoryChatController>> _controllersCache = {};
final Map<ThreadKey, Capsule<bool>> _typingCache = {};

// Per-thread appenders registered by each subscribing capsule's [effect].
// A single call to [appendLocalMessage] fans out to all appenders so that
// the reactive list, the flutter_chat_ui controller, and future observers
// stay in sync.
final Map<ThreadKey, List<void Function(ChatMessage)>> _appenders = {};

// Bumped by [resetMessagesCapsuleCache]. Each capsule closure snapshots
// this at creation and its listeners drop events after a mismatch — so
// old rearch-container-managed capsules go dormant on signout instead of
// polluting a subsequent user's chat state.
int _cacheGeneration = 0;

/// Family capsule: reactive `List<ChatMessage>` for [threadKey]. Kept for
/// group chat pages that haven't migrated to [chatControllerCapsule] yet.
Capsule<List<ChatMessage>> messagesCapsule(ThreadKey threadKey) {
  return _messagesCache.putIfAbsent(threadKey, () {
    final myGeneration = _cacheGeneration;
    List<ChatMessage> capsule(CapsuleHandle use) {
      final events = use(xmppEventsCapsule);
      final myUserId = use(authCapsule).me?.id;
      final slot = use.data<List<ChatMessage>>(const []);

      use.effect(() {
        void append(ChatMessage m) {
          if (myGeneration != _cacheGeneration) return;
          if (slot.value.any((existing) => existing.id == m.id)) return;
          slot.value = [...slot.value, m];
        }

        _registerAppender(threadKey, append);

        final StreamSubscription<XmppChatMessage> sub = events
            .where((e) => e is XmppChatMessage)
            .cast<XmppChatMessage>()
            .where((e) => _belongsToThread(e, threadKey))
            .listen((e) {
              if (myGeneration != _cacheGeneration) return;
              final fromLocal = _localPart(e.from);
              append(
                ChatMessage(
                  id: e.stanzaId,
                  body: e.body,
                  from: e.from,
                  to: e.to,
                  sentAt: DateTime.now(),
                  isMine: myUserId != null && fromLocal == myUserId,
                ),
              );
            });

        return () {
          _unregisterAppender(threadKey, append);
          sub.cancel();
        };
      }, [events, threadKey, myUserId]);

      return slot.value;
    }

    return capsule;
  });
}

/// Family capsule: `InMemoryChatController` for [threadKey], backing the
/// `flutter_chat_ui` `Chat` widget. Feeds identical messages to
/// [messagesCapsule] via the shared appender registry.
Capsule<InMemoryChatController> chatControllerCapsule(ThreadKey threadKey) {
  return _controllersCache.putIfAbsent(threadKey, () {
    final myGeneration = _cacheGeneration;
    InMemoryChatController capsule(CapsuleHandle use) {
      final events = use(xmppEventsCapsule);
      final xmpp = use(xmppCapsule);
      final myUserId = use(authCapsule).me?.id;
      final controller = use.disposable<InMemoryChatController>(
        InMemoryChatController.new,
        (c) => c.dispose(),
        [threadKey],
      );
      final mamCursor = use.data<int>(0);
      final isMuc = threadKey.contains('@muc.');

      // One-shot MAM hydration when the capsule is first built. Works for
      // both 1:1 (peer bare JID) and MUC (room bare JID) — the stub routes
      // on the `with` field's domain.
      use.callonce(() {
        if (myUserId != null && myGeneration == _cacheGeneration) {
          Timer.run(() => xmpp.queryMamWith(threadKey, max: 50));
        }
        return null;
      });

      use.effect(() {
        Future<void> insertOnce(Message m, {int? index}) async {
          if (myGeneration != _cacheGeneration) return;
          if (controller.messages.any((existing) => existing.id == m.id)) {
            return;
          }
          // Defensive clamp — if some other event source pushed our cursor
          // past the actual list size we'd otherwise blow up in
          // List.insert. Cap at length so insert becomes an append.
          final safeIndex = index == null
              ? null
              : (index > controller.messages.length
                    ? controller.messages.length
                    : index);
          await controller.insertMessage(m, index: safeIndex);
        }

        String senderIdFor(String fromJid, {required bool isGroupChat}) {
          if (isGroupChat) return _resourcePart(fromJid);
          return _localPart(fromJid);
        }

        void insertFromChatMessage(
          ChatMessage cm, {
          required bool isGroupChat,
          int? index,
        }) {
          final senderId = cm.isMine
              ? (myUserId ?? 'me')
              : senderIdFor(cm.from, isGroupChat: isGroupChat);
          insertOnce(_toChatUiMessage(cm, senderId), index: index);
        }

        void append(ChatMessage cm) {
          insertFromChatMessage(cm, isGroupChat: isMuc);
        }

        _registerAppender(threadKey, append);

        final StreamSubscription<XmppChatMessage> liveSub = events
            .where((e) => e is XmppChatMessage)
            .cast<XmppChatMessage>()
            .where((e) => _belongsToThread(e, threadKey))
            .listen((e) {
              if (myGeneration != _cacheGeneration) return;
              final senderId = senderIdFor(e.from, isGroupChat: e.isGroupChat);
              final isMine = myUserId != null && senderId == myUserId;
              insertFromChatMessage(
                ChatMessage(
                  id: e.stanzaId,
                  body: e.body,
                  from: e.from,
                  to: e.to,
                  sentAt: DateTime.now(),
                  isMine: isMine,
                  attachment: _fromXmpp(e.attachment),
                ),
                isGroupChat: e.isGroupChat,
              );
              // For a 1:1 message from the peer, auto-send delivery
              // receipt (XEP-0184 / XEP-0333 received) + read marker
              // (XEP-0333 displayed). We're intentionally "aggressive" on
              // displayed for the demo — the capsule is only alive while
              // the chat surface was recently visible.
              if (!isMuc && !isMine && e.stanzaId.isNotEmpty) {
                final peerBare = _bareJid(e.from);
                xmpp.sendDeliveryReceipt(
                  toBareJid: peerBare,
                  stanzaId: e.stanzaId,
                );
                xmpp.sendReadMarker(toBareJid: peerBare, stanzaId: e.stanzaId);
              }
            });

        // MAM stream: preserve chronological (oldest-first) order by
        // inserting at a monotonically-increasing top cursor.
        final StreamSubscription<XmppMamMessage> mamSub = events
            .where((e) => e is XmppMamMessage)
            .cast<XmppMamMessage>()
            .where((e) => _belongsToMamThread(e, threadKey))
            .listen((e) {
              if (myGeneration != _cacheGeneration) return;
              final senderId = senderIdFor(e.from, isGroupChat: e.isGroupChat);
              insertFromChatMessage(
                ChatMessage(
                  id: e.stanzaId,
                  body: e.body,
                  from: e.from,
                  to: e.to,
                  sentAt: e.sentAt,
                  isMine: myUserId != null && senderId == myUserId,
                  attachment: _fromXmpp(e.attachment),
                ),
                isGroupChat: e.isGroupChat,
                index: mamCursor.value,
              );
              mamCursor.value = mamCursor.value + 1;
            });

        // Delivery receipts (XEP-0184 / XEP-0333 received) — stamp
        // deliveredAt on my messages so the Chat widget upgrades the
        // status icon from "sent" to "delivered".
        final receiptSub = events
            .where((e) => e is XmppDeliveryReceipt)
            .cast<XmppDeliveryReceipt>()
            .where((e) => e.fromBare == threadKey)
            .listen((e) async {
              if (myGeneration != _cacheGeneration) return;
              await _stampStatus(
                controller,
                stanzaId: e.stanzaId,
                delivered: true,
              );
            });

        // Read markers (XEP-0333 displayed) — stamp seenAt.
        final markerSub = events
            .where((e) => e is XmppReadMarker)
            .cast<XmppReadMarker>()
            .where((e) => e.fromBare == threadKey)
            .listen((e) async {
              if (myGeneration != _cacheGeneration) return;
              await _stampStatus(controller, stanzaId: e.stanzaId, seen: true);
            });

        return () {
          _unregisterAppender(threadKey, append);
          liveSub.cancel();
          mamSub.cancel();
          receiptSub.cancel();
          markerSub.cancel();
        };
      }, [events, threadKey, myUserId]);

      return controller;
    }

    return capsule;
  });
}

/// Family capsule: `true` while the peer at [threadKey] is currently
/// typing (last `<composing/>` was recent), otherwise `false`. Auto-clears
/// on `<paused/>`, `<active/>`, `<inactive/>` or after a 6s inactivity
/// timeout so a stray composing without a paused doesn't leave the
/// indicator stuck on.
Capsule<bool> typingCapsule(ThreadKey threadKey) {
  return _typingCache.putIfAbsent(threadKey, () {
    final myGeneration = _cacheGeneration;
    bool capsule(CapsuleHandle use) {
      final events = use(xmppEventsCapsule);
      final slot = use.data<bool>(false);

      use.effect(() {
        Timer? clearTimer;
        final sub = events
            .where((e) => e is XmppChatState)
            .cast<XmppChatState>()
            .where((e) => e.fromBare == threadKey)
            .listen((e) {
              if (myGeneration != _cacheGeneration) return;
              clearTimer?.cancel();
              if (e.state == 'composing') {
                slot.value = true;
                clearTimer = Timer(const Duration(seconds: 6), () {
                  if (myGeneration == _cacheGeneration) slot.value = false;
                });
              } else {
                slot.value = false;
              }
            });
        return () {
          clearTimer?.cancel();
          sub.cancel();
        };
      }, [events, threadKey]);

      return slot.value;
    }

    return capsule;
  });
}

/// Echoes an outbound (local) [msg] into every appender registered for
/// [threadKey]. Both [messagesCapsule] and [chatControllerCapsule] register
/// their own appenders on first read, so this fans out to whichever
/// consumer(s) are live.
void appendLocalMessage(ThreadKey threadKey, ChatMessage msg) {
  final list = _appenders[threadKey];
  if (list == null) return;
  for (final fn in List.of(list)) {
    fn(msg);
  }
}

/// Clears family caches, the appender registry, and bumps the cache
/// generation counter — old rearch-container-managed capsules that
/// snapshot the previous generation will drop future events instead of
/// polluting the new user's chat state.
void resetMessagesCapsuleCache() {
  _messagesCache.clear();
  _controllersCache.clear();
  _typingCache.clear();
  _appenders.clear();
  _cacheGeneration++;
}

Message _toChatUiMessage(ChatMessage cm, String authorId) {
  final a = cm.attachment;
  if (a != null && a.isImage) {
    return Message.image(
      id: cm.id,
      authorId: authorId,
      createdAt: cm.sentAt,
      sentAt: cm.isMine ? cm.sentAt : null,
      source: a.downloadUrl,
      text: cm.body,
      size: a.size,
    );
  }
  if (a != null) {
    return Message.file(
      id: cm.id,
      authorId: authorId,
      createdAt: cm.sentAt,
      sentAt: cm.isMine ? cm.sentAt : null,
      source: a.downloadUrl,
      name: a.fileName,
      mimeType: a.mimeType,
      size: a.size,
    );
  }
  return Message.text(
    id: cm.id,
    authorId: authorId,
    createdAt: cm.sentAt,
    // `sentAt` is what makes Chat show at least the "sent" checkmark for
    // my own messages; deliveredAt/seenAt are stamped later by
    // receipt/marker events.
    sentAt: cm.isMine ? cm.sentAt : null,
    text: cm.body,
  );
}

FileDescriptor? _fromXmpp(XmppAttachment? a) {
  if (a == null) return null;
  return FileDescriptor(
    id: a.id,
    fileName: a.fileName,
    mimeType: a.mimeType,
    size: a.size,
    downloadUrl: a.url,
  );
}

/// Finds the message with [stanzaId] and calls `updateMessage` with an
/// upgraded status timeline. No-op if the id isn't in the controller.
Future<void> _stampStatus(
  InMemoryChatController controller, {
  required String stanzaId,
  bool delivered = false,
  bool seen = false,
}) async {
  final old = controller.messages
      .where((m) => m.id == stanzaId)
      .firstOrNull;
  if (old == null) return;
  final now = DateTime.now();
  final Message updated;
  switch (old) {
    case TextMessage m:
      updated = m.copyWith(
        deliveredAt: delivered || seen ? (m.deliveredAt ?? now) : m.deliveredAt,
        seenAt: seen ? (m.seenAt ?? now) : m.seenAt,
      );
    case ImageMessage m:
      updated = m.copyWith(
        deliveredAt: delivered || seen ? (m.deliveredAt ?? now) : m.deliveredAt,
        seenAt: seen ? (m.seenAt ?? now) : m.seenAt,
      );
    case FileMessage m:
      updated = m.copyWith(
        deliveredAt: delivered || seen ? (m.deliveredAt ?? now) : m.deliveredAt,
        seenAt: seen ? (m.seenAt ?? now) : m.seenAt,
      );
    default:
      return;
  }
  if (identical(updated, old)) return;
  await controller.updateMessage(old, updated);
}

void _registerAppender(ThreadKey threadKey, void Function(ChatMessage) fn) {
  _appenders.putIfAbsent(threadKey, () => []).add(fn);
}

void _unregisterAppender(ThreadKey threadKey, void Function(ChatMessage) fn) {
  final list = _appenders[threadKey];
  if (list == null) return;
  list.remove(fn);
  if (list.isEmpty) _appenders.remove(threadKey);
}

bool _belongsToThread(XmppChatMessage e, ThreadKey threadKey) {
  return _bareJid(e.from) == threadKey || _bareJid(e.to) == threadKey;
}

bool _belongsToMamThread(XmppMamMessage e, ThreadKey threadKey) {
  return _bareJid(e.from) == threadKey || _bareJid(e.to) == threadKey;
}

String _bareJid(String jid) =>
    jid.contains('/') ? jid.substring(0, jid.indexOf('/')) : jid;

String _localPart(String jid) {
  final bare = _bareJid(jid);
  final at = bare.indexOf('@');
  return at >= 0 ? bare.substring(0, at) : bare;
}

/// Returns the resource part of a full JID (the segment after `/`), which
/// for MUC messages is the sender's nick — set by our client to the
/// sender's user id.
String _resourcePart(String jid) {
  final slash = jid.indexOf('/');
  return slash >= 0 ? jid.substring(slash + 1) : jid;
}
