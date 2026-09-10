import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/auth_state_capsule.dart';
import '../state/capsules/chat_actions_capsule.dart';
import '../state/capsules/config_capsule.dart';
import '../state/capsules/messages_capsule.dart';
import '../state/capsules/roster_capsule.dart';

class BubbleChatPage extends RearchConsumer {
  const BubbleChatPage({super.key, required this.bubble});
  final RainbowBubble bubble;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final config = use(configCapsule);
    final actions = use(chatActionsCapsule);
    final me = use(authCapsule).me;
    final rosterAsync = use(rosterCapsule);
    final threadKey = '${bubble.id}@muc.${config.xmppDomain}';
    final controller = use(chatControllerCapsule(threadKey));

    // Join the MUC once per bubble; use.effect returns a no-op disposer.
    use.effect(() {
      actions.joinMuc(bubble);
      return null;
    }, [bubble.id]);

    final currentUserId = me?.id ?? 'me';
    final selfName = me?.display ?? me?.loginEmail ?? 'Me';
    final roster = switch (rosterAsync) {
      AsyncData<List<RosterEntry>>(data: final d) => d,
      _ => const <RosterEntry>[],
    };

    Future<User?> resolveUser(UserID id) async {
      if (id == currentUserId) return User(id: id, name: selfName);
      for (final r in roster) {
        if (r.peer.id == id) return User(id: id, name: r.peer.display);
      }
      // Fallback: search the bubble's own member list for a matching id.
      for (final m in bubble.members) {
        if (m.userId == id) return User(id: id, name: id);
      }
      return User(id: id, name: id);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(bubble.name),
            if (bubble.topic != null)
              Text(bubble.topic!, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: Chat(
        currentUserId: currentUserId,
        resolveUser: resolveUser,
        chatController: controller,
        onMessageSend: (text) {
          final trimmed = text.trim();
          if (trimmed.isEmpty) return;
          actions.sendGroup(bubble, trimmed);
        },
      ),
    );
  }
}
