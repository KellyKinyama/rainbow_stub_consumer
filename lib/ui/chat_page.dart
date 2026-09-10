import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_rearch/flutter_rearch.dart';

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

    final currentUserId = me?.id ?? 'me';
    final selfName = me?.display ?? me?.loginEmail ?? 'Me';

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
      body: Chat(
        currentUserId: currentUserId,
        resolveUser: resolveUser,
        chatController: controller,
        onMessageSend: (text) {
          final trimmed = text.trim();
          if (trimmed.isEmpty) return;
          actions.sendPeer(peer, trimmed);
        },
      ),
    );
  }
}
