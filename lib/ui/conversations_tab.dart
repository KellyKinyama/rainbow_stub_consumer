import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/conversations_capsule.dart';
import '../state/capsules/roster_capsule.dart';
import '../state/capsules/unread_capsule.dart';
import 'chat_page.dart';

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
    if (conversations.isEmpty) {
      return const _EmptyState();
    }
    return ListView.builder(
      itemCount: conversations.length,
      itemBuilder: (_, i) {
        final c = conversations[i];
        final badge = unread.counts[c.peerId] ?? 0;
        return ListTile(
          leading: CircleAvatar(
            child: Text(
              c.peerDisplay.isEmpty
                  ? '?'
                  : c.peerDisplay.characters.first.toUpperCase(),
            ),
          ),
          title: Text(c.peerDisplay),
          subtitle: Text(
            _subtitleFor(c),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_timeLabel(c.lastAt)),
              if (badge > 0) ...[
                const SizedBox(height: 4),
                Badge.count(count: badge),
              ],
            ],
          ),
          onTap: () => _openChatFromRoster(context, use, c.peerId),
        );
      },
    );
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ChatPage(peer: peer)));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No recent conversations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Open a contact from the Contacts tab to start chatting.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
