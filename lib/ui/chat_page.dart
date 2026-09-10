import 'dart:async';

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

class ChatPage extends RearchConsumer {
  const ChatPage({super.key, required this.peer});
  final RainbowUser peer;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final config = use(configCapsule);
    final actions = use(chatActionsCapsule);
    final me = use(authCapsule).me;
    final threadKey = '${peer.id}@${config.xmppDomain}';
    final controller = use(chatControllerCapsule(threadKey));
    final peerIsTyping = use(typingCapsule(threadKey));
    final input = use.textEditingController();

    final currentUserId = me?.id ?? 'me';
    final selfName = me?.display ?? me?.loginEmail ?? 'Me';

    // Debounced chat-state emitter: send `<composing/>` at most once every
    // 3 s while text is being typed, and `<paused/>` once idle for 3 s.
    use.effect(() {
      Timer? pauseTimer;
      var lastComposingSent = DateTime.fromMicrosecondsSinceEpoch(0);
      var wasEmpty = input.text.isEmpty;

      void onChange() {
        final now = DateTime.now();
        final isEmpty = input.text.isEmpty;
        if (isEmpty) {
          pauseTimer?.cancel();
          if (!wasEmpty) actions.sendChatState(peer, 'paused');
          wasEmpty = true;
          return;
        }
        wasEmpty = false;
        if (now.difference(lastComposingSent) > const Duration(seconds: 3)) {
          actions.sendChatState(peer, 'composing');
          lastComposingSent = now;
        }
        pauseTimer?.cancel();
        pauseTimer = Timer(const Duration(seconds: 3), () {
          actions.sendChatState(peer, 'paused');
        });
      }

      input.addListener(onChange);
      return () {
        pauseTimer?.cancel();
        input.removeListener(onChange);
      };
    }, [input, peer.id]);

    Future<User?> resolveUser(UserID id) async {
      if (id == currentUserId) {
        return User(id: id, name: selfName);
      }
      if (id == peer.id) {
        return User(id: id, name: peer.display);
      }
      return User(id: id, name: id);
    }

    return Scaffold(
      appBar: AppBar(title: Text(peer.display)),
      body: Column(
        children: [
          if (peerIsTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const IsTypingIndicator(),
                  const SizedBox(width: 8),
                  Text(
                    '${peer.display} is typing…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          Expanded(
            child: Chat(
              currentUserId: currentUserId,
              resolveUser: resolveUser,
              chatController: controller,
              builders: Builders(
                composerBuilder: (ctx) =>
                    Composer(textEditingController: input),
              ),
              onMessageSend: (text) {
                final trimmed = text.trim();
                if (trimmed.isEmpty) return;
                actions.sendPeer(peer, trimmed);
                // The composer clears on send, which will fire our
                // listener above → sends `<paused/>`.
              },
            ),
          ),
        ],
      ),
    );
  }
}
