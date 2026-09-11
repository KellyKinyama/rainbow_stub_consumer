import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/auth_state_capsule.dart';
import '../state/capsules/bubbles_capsule.dart';
import '../state/capsules/chat_actions_capsule.dart';
import '../state/capsules/roster_capsule.dart';

/// Member list + edit + invite + leave / delete for a single bubble.
/// Pushed from the info button in [BubbleChatPage].
class BubbleDetailsPage extends RearchConsumer {
  const BubbleDetailsPage({super.key, required this.bubble});
  final RainbowBubble bubble;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    // Read the live bubble from the capsule so mutations elsewhere
    // update this page in-place; fall back to the seed argument if
    // the fetch hasn't landed yet.
    final bubblesAsync = use(bubblesCapsule);
    final live = switch (bubblesAsync) {
      AsyncData<List<RainbowBubble>>(:final data) => data.firstWhere(
          (b) => b.id == bubble.id,
          orElse: () => bubble,
        ),
      _ => bubble,
    };
    final actions = use(chatActionsCapsule);
    final me = use(authCapsule).me;
    final roster = switch (use(rosterCapsule)) {
      AsyncData<List<RosterEntry>>(:final data) => data,
      _ => const <RosterEntry>[],
    };

    String peerDisplay(String userId) {
      for (final r in roster) {
        if (r.peer.id == userId) return r.peer.display;
      }
      return userId;
    }

    final myMember = live.members
        .where((m) => m.userId == (me?.id ?? ''))
        .fold<BubbleMember?>(null, (_, m) => m);
    final isOwner = myMember?.role == 'owner';
    final accepted =
        live.members.where((m) => m.status == 'accepted').toList();
    final invited =
        live.members.where((m) => m.status == 'invited').toList();

    Future<void> confirm({
      required String title,
      required String message,
      required Future<void> Function() action,
    }) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dc) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dc).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dc).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await action();
      if (context.mounted) Navigator.of(context).pop();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(live.name),
        actions: [
          if (isOwner)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit),
              onPressed: () => _editSheet(context, live, actions),
            ),
        ],
      ),
      body: ListView(
        children: [
          _Header(bubble: live),
          const Divider(height: 1),
          _sectionTitle(context, 'Members (${accepted.length})'),
          for (final m in accepted)
            ListTile(
              leading: CircleAvatar(
                child: Text(peerDisplay(m.userId).characters.first.toUpperCase()),
              ),
              title: Text(peerDisplay(m.userId)),
              subtitle: Text(m.role),
            ),
          if (invited.isNotEmpty) ...[
            _sectionTitle(context, 'Pending invitations (${invited.length})'),
            for (final m in invited)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.hourglass_empty)),
                title: Text(peerDisplay(m.userId)),
                subtitle: const Text('invited'),
              ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.person_add),
                  label: const Text('Invite from contacts'),
                  onPressed: () async {
                    final target =
                        await _pickContact(context, roster, accepted);
                    if (target == null) return;
                    try {
                      await actions.inviteToBubble(live, userId: target.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Invited ${target.display}'),
                          ),
                        );
                      }
                    } on Object catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Invite failed: $e')),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('Leave bubble'),
                  onPressed: () => confirm(
                    title: 'Leave bubble?',
                    message: 'You will stop receiving messages in ${live.name}.',
                    action: () => actions.leaveBubble(live),
                  ),
                ),
                if (isOwner) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: Icon(
                      Icons.delete_forever,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    label: Text(
                      'Delete bubble',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onPressed: () => confirm(
                      title: 'Delete bubble?',
                      message:
                          'This removes the bubble for everyone. This cannot be undone.',
                      action: () => actions.deleteBubble(live),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );

  Future<void> _editSheet(
    BuildContext context,
    RainbowBubble bubble,
    ChatActions actions,
  ) async {
    final nameCtl = TextEditingController(text: bubble.name);
    final topicCtl = TextEditingController(text: bubble.topic ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (bc) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 12,
          bottom: MediaQuery.of(bc).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit bubble', style: Theme.of(bc).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: topicCtl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Topic'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(bc).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await actions.updateBubble(
        bubble,
        name: nameCtl.text.trim().isEmpty ? null : nameCtl.text.trim(),
        topic: topicCtl.text.trim().isEmpty ? null : topicCtl.text.trim(),
      );
    } finally {
      nameCtl.dispose();
      topicCtl.dispose();
    }
  }

  Future<RainbowUser?> _pickContact(
    BuildContext context,
    List<RosterEntry> roster,
    List<BubbleMember> already,
  ) async {
    final existing = already.map((m) => m.userId).toSet();
    final options = roster
        .where((r) => !existing.contains(r.peer.id))
        .toList(growable: false);
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Everyone in your roster is already here')),
      );
      return null;
    }
    return showModalBottomSheet<RainbowUser>(
      context: context,
      showDragHandle: true,
      builder: (bc) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final r in options)
              ListTile(
                leading: CircleAvatar(
                  child: Text(r.peer.display.characters.first.toUpperCase()),
                ),
                title: Text(r.peer.display),
                subtitle: Text(r.peer.loginEmail),
                onTap: () => Navigator.of(bc).pop(r.peer),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.bubble});
  final RainbowBubble bubble;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            child: Text(
              bubble.name.isEmpty
                  ? '?'
                  : bubble.name.characters.first.toUpperCase(),
              style: const TextStyle(fontSize: 32),
            ),
          ),
          const SizedBox(height: 8),
          Text(bubble.name, style: Theme.of(context).textTheme.titleLarge),
          if (bubble.topic?.isNotEmpty ?? false) ...[
            const SizedBox(height: 4),
            Text(
              bubble.topic!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
