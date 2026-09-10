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

/// Family capsule: reactive `List<ChatMessage>` for [threadKey]. Kept for
/// group chat pages that haven't migrated to [chatControllerCapsule] yet.
Capsule<List<ChatMessage>> messagesCapsule(ThreadKey threadKey) {
  return _messagesCache.putIfAbsent(threadKey, () {
    List<ChatMessage> capsule(CapsuleHandle use) {
      final events = use(xmppEventsCapsule);
      final myUserId = use(authCapsule).me?.id;
      final slot = use.data<List<ChatMessage>>(const []);

      use.effect(() {
        void append(ChatMessage m) {
          if (slot.value.any((existing) => existing.id == m.id)) return;
          slot.value = [...slot.value, m];
        }

        _registerAppender(threadKey, append);

        final StreamSubscription<XmppChatMessage> sub = events
            .where((e) => e is XmppChatMessage)
            .cast<XmppChatMessage>()
            .where((e) => _belongsToThread(e, threadKey))
            .listen((e) {
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

      // One-shot MAM hydration when the capsule is first built for this
      // 1:1 thread. MUC hydration is Phase E.
      use.callonce(() {
        if (myUserId != null && !threadKey.contains('@muc.')) {
          Timer.run(() => xmpp.queryMamWith(threadKey, max: 50));
        }
        return null;
      });

      use.effect(() {
        Future<void> insertOnce(Message m, {int? index}) async {
          if (controller.messages.any((existing) => existing.id == m.id)) {
            return;
          }
          await controller.insertMessage(m, index: index);
        }

        void append(ChatMessage cm) {
          insertOnce(_toChatUiMessage(cm, myUserId));
        }

        _registerAppender(threadKey, append);

        final StreamSubscription<XmppChatMessage> liveSub = events
            .where((e) => e is XmppChatMessage)
            .cast<XmppChatMessage>()
            .where((e) => _belongsToThread(e, threadKey))
            .listen((e) {
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

        // MAM stream: preserve chronological (oldest-first) order by
        // inserting at a monotonically-increasing top cursor.
        final StreamSubscription<XmppMamMessage> mamSub = events
            .where((e) => e is XmppMamMessage)
            .cast<XmppMamMessage>()
            .where((e) => _belongsToMamThread(e, threadKey))
            .listen((e) {
              final fromLocal = _localPart(e.from);
              final msg = _toChatUiMessage(
                ChatMessage(
                  id: e.stanzaId,
                  body: e.body,
                  from: e.from,
                  to: e.to,
                  sentAt: e.sentAt,
                  isMine: myUserId != null && fromLocal == myUserId,
                ),
                myUserId,
              );
              insertOnce(msg, index: mamCursor.value);
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

/// Test-only: clears family caches and the appender registry.
void resetMessagesCapsuleCache() {
  _messagesCache.clear();
  _controllersCache.clear();
  _appenders.clear();
}

Message _toChatUiMessage(ChatMessage cm, String? myUserId) {
  final authorId = cm.isMine ? (myUserId ?? 'me') : _localPart(cm.from);
  return Message.text(
    id: cm.id,
    authorId: authorId,
    createdAt: cm.sentAt,
    text: cm.body,
  );
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
