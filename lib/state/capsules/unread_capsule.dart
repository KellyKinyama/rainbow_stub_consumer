import 'dart:async';

import 'package:rearch/rearch.dart';

import '../../rainbow/xmpp_client.dart';
import 'auth_state_capsule.dart';
import 'xmpp_capsule.dart';

/// Per-thread unread counters keyed by:
///   - the peer's bare-JID local part for 1:1 conversations, or
///   - the bubble id (MUC local part) for group chats.
///
/// Increments on any inbound [XmppChatMessage] with a non-empty body
/// that isn't from the local user. Consumers reset by calling
/// [UnreadController.markRead] when the user opens the thread.
class UnreadController {
  const UnreadController({
    required this.counts,
    required this.markRead,
    required this.total,
  });

  final Map<String, int> counts;
  final int total;
  final void Function(String threadKey) markRead;
}

UnreadController unreadCapsule(CapsuleHandle use) {
  final events = use(xmppEventsCapsule);
  final myId = use(authCapsule).me?.id;
  final slot = use.data<Map<String, int>>(const <String, int>{});

  use.effect(() {
    if (myId == null) {
      slot.value = const <String, int>{};
      return null;
    }
    final StreamSubscription<XmppChatMessage> sub = events
        .where((e) => e is XmppChatMessage)
        .cast<XmppChatMessage>()
        .where((e) => e.body.isNotEmpty)
        .listen((e) {
          final fromLocal = _localPart(e.from);
          if (fromLocal == myId) return;
          final key = e.isGroupChat ? _localPart(e.to) : fromLocal;
          if (key.isEmpty) return;
          final next = Map<String, int>.from(slot.value);
          next[key] = (next[key] ?? 0) + 1;
          slot.value = next;
        });
    return sub.cancel;
  }, [events, myId]);

  void markRead(String threadKey) {
    if (!slot.value.containsKey(threadKey)) return;
    final next = Map<String, int>.from(slot.value)..remove(threadKey);
    slot.value = next;
  }

  final total = slot.value.values.fold<int>(0, (a, b) => a + b);
  return UnreadController(counts: slot.value, total: total, markRead: markRead);
}

String _localPart(String jid) {
  final at = jid.indexOf('@');
  return at < 0 ? jid : jid.substring(0, at);
}
