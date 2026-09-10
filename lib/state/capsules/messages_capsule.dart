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
              insertFromChatMessage(
                ChatMessage(
                  id: e.stanzaId,
                  body: e.body,
                  from: e.from,
                  to: e.to,
                  sentAt: DateTime.now(),
                  isMine: myUserId != null && senderId == myUserId,
                ),
                isGroupChat: e.isGroupChat,
              );
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
                ),
                isGroupChat: e.isGroupChat,
                index: mamCursor.value,
              );
              mamCursor.value = mamCursor.value + 1;
            });

        return () {
          _unregisterAppender(threadKey, append);
          liveSub.cancel();
          mamSub.cancel();
        };
      }, [events, threadKey, myUserId]);

      return controller;
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
  _appenders.clear();
  _cacheGeneration++;
}

Message _toChatUiMessage(ChatMessage cm, String authorId) => Message.text(
  id: cm.id,
  authorId: authorId,
  createdAt: cm.sentAt,
  text: cm.body,
);

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
