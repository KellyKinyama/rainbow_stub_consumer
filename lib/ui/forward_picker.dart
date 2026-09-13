import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/bubbles_capsule.dart';
import '../state/capsules/roster_capsule.dart';

/// Result of the forward picker. Exactly one of [peer] / [bubble] is
/// non-null.
sealed class ForwardTarget {
  const ForwardTarget();
}

class ForwardPeerTarget extends ForwardTarget {
  const ForwardPeerTarget(this.peer);
  final RainbowUser peer;
}

class ForwardBubbleTarget extends ForwardTarget {
  const ForwardBubbleTarget(this.bubble);
  final RainbowBubble bubble;
}

/// Full-screen picker listing the current user's contacts + joined
/// bubbles. Returns `null` if the user backs out.
Future<ForwardTarget?> pickForwardTarget(BuildContext context) {
  return Navigator.of(context).push<ForwardTarget>(
    MaterialPageRoute(
      builder: (_) => const _ForwardPickerPage(),
      fullscreenDialog: true,
    ),
  );
}

class _ForwardPickerPage extends RearchConsumer {
  const _ForwardPickerPage();

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final roster = use(rosterCapsule);
    final bubbles = use(bubblesCapsule);
    final peers = switch (roster) {
      AsyncData<List<RosterEntry>>(:final data) => data,
      _ => const <RosterEntry>[],
    };
    final rooms = switch (bubbles) {
      AsyncData<List<RainbowBubble>>(:final data) => data,
      _ => const <RainbowBubble>[],
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Forward to…')),
      body: ListView(
        children: [
          if (rooms.isNotEmpty) ...[
            const _SectionHeader(text: 'Rooms'),
            for (final b in rooms)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.forum)),
                title: Text(b.name),
                subtitle: b.topic == null || b.topic!.isEmpty
                    ? null
                    : Text(b.topic!),
                onTap: () => Navigator.of(context).pop(ForwardBubbleTarget(b)),
              ),
          ],
          if (peers.isNotEmpty) ...[
            const _SectionHeader(text: 'Contacts'),
            for (final entry in peers)
              ListTile(
                leading: CircleAvatar(child: Text(_initial(entry.peer))),
                title: Text(entry.peer.display),
                subtitle: Text(entry.peer.loginEmail),
                onTap: () =>
                    Navigator.of(context).pop(ForwardPeerTarget(entry.peer)),
              ),
          ],
          if (rooms.isEmpty && peers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No contacts or rooms to forward to.')),
            ),
        ],
      ),
    );
  }

  static String _initial(RainbowUser u) {
    final label = u.display;
    return label.isEmpty ? '?' : label.characters.first.toUpperCase();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
