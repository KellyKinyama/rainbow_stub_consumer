import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/conversations_capsule.dart';
import '../state/capsules/detail_selection_capsule.dart';
import '../state/capsules/presence_capsule.dart';
import '../state/capsules/roster_capsule.dart';
import '../state/capsules/unread_capsule.dart';
import '../state/models/presence.dart';
import 'phone_empty.dart';
import 'phone_row_tile.dart';
import 'responsive.dart';
import 'theme_tokens.dart';

/// "Recent" tab — mirrors the RN sample's ``Conversations`` list.
/// Session-scoped: entries are populated as XMPP 1:1 messages arrive
/// while the app is running. Empty on first launch until either the
/// peer sends something or the user opens a peer from Contacts and
/// exchanges a message.
class ConversationsTab extends RearchConsumer {
  const ConversationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final conversations = use(conversationsCapsule);
    final unread = use(unreadCapsule);
    final selection = use(detailSelectionCapsule);
    final presence = use(presenceCapsule);
    if (conversations.isEmpty) {
      return const _EmptyState();
    }
    return ListView.separated(
      itemCount: conversations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (_, i) {
        final c = conversations[i];
        final badge = unread.counts[c.peerId] ?? 0;
        return PhoneRowTile(
          avatar: PhoneAvatar(
            label: c.peerDisplay,
            presenceColor: _onlineDot(c.peerId, presence),
          ),
          title: c.peerDisplay,
          subtitle: _subtitleFor(c),
          trailingText: _timeLabel(c.lastAt),
          unreadCount: badge,
          onTap: () => _openChatFromRoster(context, use, c.peerId, selection),
        );
      },
    );
  }

  /// Green dot when the peer is online, otherwise none (WhatsApp-style —
  /// only a positive presence is surfaced in the list).
  static Color? _onlineDot(String peerId, Map<String, Presence> map) {
    for (final entry in map.entries) {
      final local = entry.key.contains('@')
          ? entry.key.substring(0, entry.key.indexOf('@'))
          : entry.key;
      if (local != peerId) continue;
      final show = entry.value.show;
      return (show == 'online' || show == 'chat')
          ? PhoneTokens.callActive
          : null;
    }
    return null;
  }

  static String _subtitleFor(ConversationSummary c) {
    final prefix = c.direction == ConversationDirection.outgoing ? 'You: ' : '';
    return '$prefix${c.lastBody}';
  }

  static String _timeLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(t.year, t.month, t.day);
    if (that == today) {
      return '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.day}/${t.month}';
  }

  void _openChatFromRoster(
    BuildContext context,
    WidgetHandle use,
    String peerId,
    ValueWrapper<ChatSelection?> selection,
  ) {
    final rosterAsync = use(rosterCapsule);
    final entries = switch (rosterAsync) {
      AsyncData<List<RosterEntry>>(:final data) => data,
      _ => const <RosterEntry>[],
    };
    final match = entries
        .where((e) => e.peer.id == peerId)
        .toList(growable: false);
    final peer = match.isEmpty
        ? RainbowUser(id: peerId, loginEmail: peerId)
        : match.first.peer;
    openPeerChat(context, selection, peer);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const PhoneNoItems(
      icon: Icons.chat_bubble_outline,
      label: 'No recent conversations. Open a contact to start chatting.',
    );
  }
}
