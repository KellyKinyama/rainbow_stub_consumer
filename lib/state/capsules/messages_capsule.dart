import 'dart:async';

import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import '../../rainbow/xmpp_client.dart';
import 'xmpp_capsule.dart';

/// Bare-JID of the peer or bubble whose thread we want to watch. For MUC
/// chats this is the bubble's room JID (e.g. `room-xyz@muc.localhost`);
/// for 1:1 chats it's the peer's bare JID.
typedef ThreadKey = String;

// Rearch identifies capsules by reference equality. To make the family
// pattern work, cache one Capsule instance per [ThreadKey] so repeated
// calls with the same key return the same capsule.
final Map<ThreadKey, Capsule<List<ChatMessage>>> _messagesCache = {};

/// Family capsule: returns the ordered list of messages for [threadKey].
///
/// Hydration from persisted history (REST or MAM) is intentionally
/// deferred to Phase D — the initial value is empty and messages are
/// appended live from the XMPP stream.
Capsule<List<ChatMessage>> messagesCapsule(ThreadKey threadKey) {
  return _messagesCache.putIfAbsent(threadKey, () {
    List<ChatMessage> capsule(CapsuleHandle use) {
      final events = use(xmppEventsCapsule);
      final slot = use.data<List<ChatMessage>>(const []);

      use.effect(() {
        final StreamSubscription<XmppChatMessage> sub = events
            .where((e) => e is XmppChatMessage)
            .cast<XmppChatMessage>()
            .where((e) => _belongsToThread(e, threadKey))
            .listen((e) {
              slot.value = [
                ...slot.value,
                ChatMessage(
                  id: e.stanzaId,
                  body: e.body,
                  from: e.from,
                  to: e.to,
                  sentAt: DateTime.now(),
                ),
              ];
            });
        return sub.cancel;
      }, [events, threadKey]);

      return slot.value;
    }

    return capsule;
  });
}

/// Clears the family cache. Test-only helper — production code should
/// never need to call this, but tests routinely swap containers and want
/// a fresh registry.
void resetMessagesCapsuleCache() => _messagesCache.clear();

bool _belongsToThread(XmppChatMessage e, ThreadKey threadKey) {
  String bare(String jid) => jid.contains('/') ? jid.substring(0, jid.indexOf('/')) : jid;
  return bare(e.from) == threadKey || bare(e.to) == threadKey;
}
