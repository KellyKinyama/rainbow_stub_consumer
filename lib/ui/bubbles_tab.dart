import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/bubble_invitations_capsule.dart';
import '../state/capsules/bubbles_capsule.dart';
import '../state/capsules/chat_actions_capsule.dart';
import 'bubble_chat_page.dart';

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
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createBubble(context, actions),
        child: const Icon(Icons.add),
      ),
    );
  }

  static Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _BubblesBody extends StatelessWidget {
  const _BubblesBody({
    required this.pendingInvites,
    required this.list,
    required this.totalCount,
    required this.query,
    required this.onQueryChanged,
    required this.onAccept,
    required this.onDecline,
  });
  final List<RainbowBubble> pendingInvites;
  final List<RainbowBubble> list;
  final int totalCount;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final Future<void> Function(RainbowBubble) onAccept;
  final Future<void> Function(RainbowBubble) onDecline;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search bubbles',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              filled: true,
            ),
          ),
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
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: Text('No bubbles yet')),
                )
              else if (list.isEmpty && query.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(48),
                  child: Center(child: Text('No match for "$query"')),
                )
              else
                for (final b in list)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.forum)),
                    title: Text(b.name),
                    subtitle: Text(b.topic ?? '${b.members.length} members'),
                    trailing: const Icon(Icons.chevron_right),
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
