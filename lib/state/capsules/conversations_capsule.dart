import 'dart:async';

import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import '../../rainbow/xmpp_client.dart';
import '../conversations_mirror.dart';
import 'auth_state_capsule.dart';
import 'conversations_mirror_capsule.dart';
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
  final xmpp = use(xmppCapsule);
  final myId = use(authCapsule).me?.id;
  final mirror = use(conversationsMirrorCapsule);
  final roster = switch (use(rosterCapsule)) {
    AsyncData<List<RosterEntry>>(:final data) => data,
    _ => const <RosterEntry>[],
  };
  final slot = use.data<Map<String, ConversationSummary>>(
    const <String, ConversationSummary>{},
  );
  final hydrated = use.data<String?>(null);

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

    // Hydrate from disk once per user before any live traffic lands.
    if (hydrated.value != myId) {
      hydrated.value = myId;
      scheduleMicrotask(() async {
        final stored = await mirror.read(myId);
        if (stored.isEmpty) return;
        final next = Map<String, ConversationSummary>.from(slot.value);
        for (final s in stored) {
          final existing = next[s.peerId];
          if (existing != null && existing.lastAt.isAfter(s.lastAt)) continue;
          next[s.peerId] = ConversationSummary(
            peerId: s.peerId,
            peerDisplay: s.peerDisplay,
            lastBody: s.lastBody,
            lastAt: s.lastAt,
            direction: s.directionOutgoing
                ? ConversationDirection.outgoing
                : ConversationDirection.incoming,
          );
        }
        slot.value = next;
      });
    }

    void persist(Map<String, ConversationSummary> map) {
      final rows = map.values
          .map(
            (c) => StoredConversation(
              peerId: c.peerId,
              peerDisplay: c.peerDisplay,
              lastBody: c.lastBody,
              lastAt: c.lastAt,
              directionOutgoing: c.direction == ConversationDirection.outgoing,
            ),
          )
          .toList(growable: false);
      unawaited(mirror.write(myId, rows));
    }

    void fold({
      required String from,
      required String to,
      required String body,
      required DateTime sentAt,
    }) {
      if (body.isEmpty) return;
      final fromLocal = _localPart(from);
      final toLocal = _localPart(to);
      final peerId = fromLocal == myId ? toLocal : fromLocal;
      if (peerId.isEmpty) return;
      final direction = fromLocal == myId
          ? ConversationDirection.outgoing
          : ConversationDirection.incoming;
      final existing = slot.value[peerId];
      if (existing != null && existing.lastAt.isAfter(sentAt)) return;
      final next = <String, ConversationSummary>{
        ...slot.value,
        peerId: ConversationSummary(
          peerId: peerId,
          peerDisplay: peerDisplayFor(peerId),
          lastBody: body,
          lastAt: sentAt,
          direction: direction,
        ),
      };
      slot.value = next;
      persist(next);
    }

    final subLive = events
        .where((e) => e is XmppChatMessage)
        .cast<XmppChatMessage>()
        .where((e) => !e.isGroupChat)
        .listen(
          (e) => fold(
            from: e.from,
            to: e.to,
            body: e.body,
            sentAt: DateTime.now(),
          ),
        );

    final subMam = events
        .where((e) => e is XmppMamMessage)
        .cast<XmppMamMessage>()
        .where((e) => !e.isGroupChat)
        .listen(
          (e) => fold(from: e.from, to: e.to, body: e.body, sentAt: e.sentAt),
        );

    final subConnected = events.where((e) => e is XmppConnected).listen((_) {
      // XEP-0313 bootstrap: pull the last 50 archived 1:1 stanzas so
      // Recent shows past conversations after a fresh sign-in.
      try {
        xmpp.queryMamAll(max: 50);
      } catch (_) {}
    });

    // Fire once on mount if we're already connected (the effect may
    // run after XmppConnected has already emitted).
    if (xmpp.isConnected) {
      try {
        xmpp.queryMamAll(max: 50);
      } catch (_) {}
    }

    return () {
      subLive.cancel();
      subMam.cancel();
      subConnected.cancel();
    };
  }, [events, xmpp, myId]);

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
