import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/config_capsule.dart';
import '../state/capsules/group_call_capsule.dart';

/// Bubble-scoped group-call strip at the top of `BubbleChatPage`.
class GroupCallBanner extends RearchConsumer {
  const GroupCallBanner({super.key, required this.bubble});
  final RainbowBubble bubble;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final manager = use(groupCallManagerCapsule);
    final config = use(configCapsule);
    if (!manager.isEnabled) return const SizedBox.shrink();
    final roomJid = '${bubble.id}@muc.${config.xmppDomain}';
    return ListenableBuilder(
      listenable: manager,
      builder: (ctx, _) {
        if (manager.joinedCalls.containsKey(roomJid)) {
          return _InCallStrip(
            onLeave: () => manager.leaveGroupCall(roomJid, announceEnd: false),
          );
        }
        final marker = manager.openCallIn(roomJid);
        if (marker != null) {
          return _JoinStrip(
            initiator: marker.fromResource,
            onJoin: () =>
                manager.joinGroupCall(roomBareJid: roomJid, sid: marker.sid),
          );
        }
        return _StartStrip(
          onStartAudio: () => manager.startGroupCall(bubble: bubble),
          onStartVideo: () =>
              manager.startGroupCall(bubble: bubble, video: true),
        );
      },
    );
  }
}

class _StartStrip extends StatelessWidget {
  const _StartStrip({required this.onStartAudio, required this.onStartVideo});
  final VoidCallback onStartAudio;
  final VoidCallback onStartVideo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.groups_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Group call',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.call),
              label: const Text('Audio'),
              onPressed: onStartAudio,
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              icon: const Icon(Icons.videocam),
              label: const Text('Video'),
              onPressed: onStartVideo,
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinStrip extends StatelessWidget {
  const _JoinStrip({required this.initiator, required this.onJoin});
  final String initiator;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.groups),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Call in progress · started by $initiator',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.call),
              label: const Text('Join'),
              onPressed: onJoin,
            ),
          ],
        ),
      ),
    );
  }
}

class _InCallStrip extends StatelessWidget {
  const _InCallStrip({required this.onLeave});
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.groups),
            const SizedBox(width: 12),
            const Expanded(child: Text('You are in this group call')),
            OutlinedButton.icon(
              icon: const Icon(Icons.call_end),
              label: const Text('Leave'),
              onPressed: onLeave,
            ),
          ],
        ),
      ),
    );
  }
}
