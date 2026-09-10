import 'dart:async';

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

// Per-thread appender registered by the capsule's [effect]. Actions
// (e.g. `chatActionsCapsule.sendPeer`) call it to echo the user's own
// message into the live list without waiting for a server carbon.
final Map<ThreadKey, void Function(ChatMessage)> _appenders = {};

/// Family capsule: returns the ordered list of messages for [threadKey].
///
/// Hydration from persisted history (REST or MAM) is intentionally
/// deferred to Phase D — the initial value is empty and messages are
/// appended live from the XMPP stream and from local send-echo.
Capsule<List<ChatMessage>> messagesCapsule(ThreadKey threadKey) {
  return _messagesCache.putIfAbsent(threadKey, () {
    List<ChatMessage> capsule(CapsuleHandle use) {
      final events = use(xmppEventsCapsule);
      final myUserId = use(authCapsule).me?.id;
      final slot = use.data<List<ChatMessage>>(const []);

      use.effect(() {
        void append(ChatMessage m) {
          slot.value = [...slot.value, m];
        }

        _appenders[threadKey] = append;

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
          if (identical(_appenders[threadKey], append)) {
            _appenders.remove(threadKey);
          }
          sub.cancel();
        };
      }, [events, threadKey, myUserId]);

      return slot.value;
    }

    return capsule;
  });
}

/// Echoes an outbound (local) [msg] into [threadKey]'s live list.
///
/// No-op if the thread's messages capsule has never been read in the
/// current container — matches the previous RainbowSession semantics
/// (an unopened thread has nothing to render into).
void appendLocalMessage(ThreadKey threadKey, ChatMessage msg) {
  _appenders[threadKey]?.call(msg);
}

/// Clears both the family cache and the appender registry. Test-only.
void resetMessagesCapsuleCache() {
  _messagesCache.clear();
  _appenders.clear();
}

bool _belongsToThread(XmppChatMessage e, ThreadKey threadKey) {
  return _bareJid(e.from) == threadKey || _bareJid(e.to) == threadKey;
}

String _bareJid(String jid) =>
    jid.contains('/') ? jid.substring(0, jid.indexOf('/')) : jid;

String _localPart(String jid) {
  final bare = _bareJid(jid);
  final at = bare.indexOf('@');
  return at >= 0 ? bare.substring(0, at) : bare;
}
