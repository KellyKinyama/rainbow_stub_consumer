import 'dart:async';

import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import '../../rainbow/xmpp_client.dart';
import 'auth_state_capsule.dart';
import 'roster_capsule.dart';
import 'xmpp_capsule.dart';

/// One row in the recent-conversations list.
class ConversationSummary {
  ConversationSummary({
    required this.peerId,
    required this.peerDisplay,
    required this.lastBody,
    required this.lastAt,
    required this.direction,
  });

  final String peerId;
  final String peerDisplay;
  final String lastBody;
  final DateTime lastAt;
  final ConversationDirection direction;
}

enum ConversationDirection { incoming, outgoing }

/// Recent 1:1 conversations for the signed-in user, sorted by last
/// activity descending. Reduces every [XmppChatMessage] the client
/// observes while it's alive. Group-chat messages are ignored (those
/// live in `bubbles_capsule`).
///
/// Session-scoped: conversations that pre-date the current sign-in
/// don't appear until either the peer sends something OR the user
/// opens the thread (which will lazily hydrate via MAM in
/// `messages_capsule`). A proper "all-history" surface would need a
/// server-side conversations endpoint (see ROADMAP § 1.3).
List<ConversationSummary> conversationsCapsule(CapsuleHandle use) {
  final events = use(xmppEventsCapsule);
  final myId = use(authCapsule).me?.id;
  final roster = switch (use(rosterCapsule)) {
    AsyncData<List<RosterEntry>>(:final data) => data,
    _ => const <RosterEntry>[],
  };
  final slot = use.data<Map<String, ConversationSummary>>(
    const <String, ConversationSummary>{},
  );

  String peerDisplayFor(String peerId) {
    for (final r in roster) {
      if (r.peer.id == peerId) return r.peer.display;
    }
    return peerId;
  }

  use.effect(() {
    if (myId == null) {
      slot.value = const <String, ConversationSummary>{};
      return null;
    }
    final StreamSubscription<XmppChatMessage> sub = events
        .where((e) => e is XmppChatMessage)
        .cast<XmppChatMessage>()
        .where((e) => !e.isGroupChat && e.body.isNotEmpty)
        .listen((e) {
          final fromLocal = _localPart(e.from);
          final toLocal = _localPart(e.to);
          // Peer is whoever is NOT me on the stanza.
          final peerId = fromLocal == myId ? toLocal : fromLocal;
          if (peerId.isEmpty) return;
          final direction = fromLocal == myId
              ? ConversationDirection.outgoing
              : ConversationDirection.incoming;
          slot.value = <String, ConversationSummary>{
            ...slot.value,
            peerId: ConversationSummary(
              peerId: peerId,
              peerDisplay: peerDisplayFor(peerId),
              lastBody: e.body,
              lastAt: DateTime.now(),
              direction: direction,
            ),
          };
        });
    return sub.cancel;
  }, [events, myId]);

  // Roster may arrive after some XmppChatMessage events (bootstrap race
  // or a same-connection add). Re-resolve display names on every build
  // so a stale raw user id gets replaced once the roster catches up.
  final resolved = <String, ConversationSummary>{};
  for (final entry in slot.value.entries) {
    final live = peerDisplayFor(entry.key);
    resolved[entry.key] = live == entry.value.peerDisplay
        ? entry.value
        : ConversationSummary(
            peerId: entry.value.peerId,
            peerDisplay: live,
            lastBody: entry.value.lastBody,
            lastAt: entry.value.lastAt,
            direction: entry.value.direction,
          );
  }

  final list = resolved.values.toList()
    ..sort((a, b) => b.lastAt.compareTo(a.lastAt));
  return list;
}

String _localPart(String jid) {
  final at = jid.indexOf('@');
  if (at < 0) return jid;
  final bare = jid.substring(0, at);
  return bare;
}
