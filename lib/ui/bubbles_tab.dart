import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/bubble_invitations_capsule.dart';
import '../state/capsules/bubbles_capsule.dart';
import '../state/capsules/chat_actions_capsule.dart';
import '../state/capsules/unread_capsule.dart';
import 'bubble_chat_page.dart';
import 'phone_empty.dart';
import 'phone_row_tile.dart';
import 'phone_search_field.dart';
import 'phone_section_heading.dart';

class BubblesTab extends RearchConsumer {
  const BubblesTab({super.key});

  Future<void> _createBubble(BuildContext context, ChatActions actions) async {
    final controller = TextEditingController();
    var busy = false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const Text('New bubble'),
          content: TextField(
            controller: controller,
            autofocus: true,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final name = controller.text.trim();
                      if (name.isEmpty) return;
                      setState(() => busy = true);
                      try {
                        await actions.createBubble(name);
                        if (dialogCtx.mounted) {
                          Navigator.of(dialogCtx).pop(true);
                        }
                      } on Object catch (e) {
                        setState(() => busy = false);
                        if (dialogCtx.mounted) {
                          ScaffoldMessenger.of(dialogCtx).showSnackBar(
                            SnackBar(content: Text('Create failed: $e')),
                          );
                        }
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Bubble created')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final bubblesAsync = use(bubblesCapsule);
    final invites = use(bubbleInvitationsCapsule);
    final actions = use(chatActionsCapsule);
    final unread = use(unreadCapsule);
    final refresher = use(bubblesRefresherCapsule);
    final (query, setQuery) = use.state<String>('');
    final normalized = query.toLowerCase().trim();
    bool matches(RainbowBubble b) {
      if (normalized.isEmpty) return true;
      return b.name.toLowerCase().contains(normalized) ||
          (b.topic ?? '').toLowerCase().contains(normalized);
    }

    final pendingInvites = switch (invites.entries) {
      AsyncData<List<RainbowBubble>>(:final data) => data,
      _ => const <RainbowBubble>[],
    };

    final body = switch (bubblesAsync) {
      AsyncLoading<List<RainbowBubble>>() => const Center(
        child: CircularProgressIndicator(),
      ),
      AsyncError<List<RainbowBubble>>(:final error) => Center(
        child: Text('Bubbles failed: $error'),
      ),
      AsyncData<List<RainbowBubble>>(data: final list) => _BubblesBody(
        pendingInvites: pendingInvites,
        list: list.where(matches).toList(growable: false),
        totalCount: list.length,
        query: query,
        unread: unread.counts,
        onQueryChanged: setQuery,
        onAccept: (b) async {
          await actions.acceptBubbleInvitation(b);
          await invites.refresh();
        },
        onDecline: (b) async {
          await actions.declineBubbleInvitation(b);
          await invites.refresh();
        },
      ),
    };

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          refresher.bump();
          await invites.refresh();
          // Await a beat so the pull-to-refresh spinner is visibly held.
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
        child: body,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createBubble(context, actions),
        child: const Icon(Icons.add),
      ),
    );
  }

  static Widget _sectionTitle(BuildContext context, String text) =>
      PhoneSectionHeading(text: text);
}

class _BubblesBody extends StatelessWidget {
  const _BubblesBody({
    required this.pendingInvites,
    required this.list,
    required this.totalCount,
    required this.query,
    required this.unread,
    required this.onQueryChanged,
    required this.onAccept,
    required this.onDecline,
  });
  final List<RainbowBubble> pendingInvites;
  final List<RainbowBubble> list;
  final int totalCount;
  final String query;
  final Map<String, int> unread;
  final ValueChanged<String> onQueryChanged;
  final Future<void> Function(RainbowBubble) onAccept;
  final Future<void> Function(RainbowBubble) onDecline;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PhoneSearchField(
          hint: 'Search bubbles',
          onChanged: onQueryChanged,
        ),
        Expanded(
          child: ListView(
            children: [
              if (pendingInvites.isNotEmpty) ...[
                BubblesTab._sectionTitle(
                  context,
                  'Invitations (${pendingInvites.length})',
                ),
                for (final b in pendingInvites)
                  _InvitationTile(
                    bubble: b,
                    onAccept: () => onAccept(b),
                    onDecline: () => onDecline(b),
                  ),
                const Divider(),
              ],
              if (totalCount == 0 && pendingInvites.isEmpty)
                const PhoneNoItems(
                  icon: Icons.forum_outlined,
                  label: 'No bubbles yet. Tap the + button to create one.',
                )
              else if (list.isEmpty && query.isNotEmpty)
                PhoneNoItems(
                  icon: Icons.search_off,
                  label: 'No match for "$query"',
                )
              else
                for (final b in list)
                  PhoneRowTile(
                    avatar: PhoneAvatar(label: b.name, icon: Icons.forum),
                    title: b.name,
                    subtitle: b.topic ?? '${b.members.length} members',
                    unreadCount: unread[b.id] ?? 0,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BubbleChatPage(bubble: b),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InvitationTile extends StatelessWidget {
  const _InvitationTile({
    required this.bubble,
    required this.onAccept,
    required this.onDecline,
  });
  final RainbowBubble bubble;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.mail_outline)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    bubble.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if ((bubble.topic ?? '').isNotEmpty)
                    Text(
                      bubble.topic!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Decline',
              icon: const Icon(Icons.close),
              onPressed: onDecline,
            ),
            IconButton(
              tooltip: 'Accept',
              icon: Icon(Icons.check, color: scheme.primary),
              onPressed: onAccept,
            ),
          ],
        ),
      ),
    );
  }
}
