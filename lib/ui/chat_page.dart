import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/auth_state_capsule.dart';
import '../state/capsules/chat_actions_capsule.dart';
import '../state/capsules/config_capsule.dart';
import '../state/capsules/messages_capsule.dart';
import 'attachment_picker.dart';

const _quickReactEmojis = ['👍', '❤️', '😂', '😮', '🎉', '🔥'];

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
    final (replyingTo, setReplyingTo) = use.state<Message?>(null);
    final (editing, setEditing) = use.state<TextMessage?>(null);

    final currentUserId = me?.id ?? 'me';
    final selfName = me?.display ?? me?.loginEmail ?? 'Me';

    // Debounced chat-state emitter.
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
      if (id == currentUserId) return User(id: id, name: selfName);
      if (id == peer.id) return User(id: id, name: peer.display);
      return User(id: id, name: id);
    }

    String previewOf(Message m) => switch (m) {
      TextMessage m => m.text,
      ImageMessage m => '📷 ${m.text ?? 'image'}',
      FileMessage m => '📎 ${m.name}',
      _ => 'message',
    };

    void beginEdit(TextMessage m) {
      setEditing(m);
      setReplyingTo(null);
      input.text = m.text;
      input.selection = TextSelection.fromPosition(
        TextPosition(offset: input.text.length),
      );
    }

    void beginReply(Message m) {
      setReplyingTo(m);
      setEditing(null);
    }

    void clearBanner() {
      if (editing != null) input.clear();
      setEditing(null);
      setReplyingTo(null);
    }

    Future<void> onLongPress(
      BuildContext ctx,
      Message m, {
      required int index,
      required LongPressStartDetails details,
    }) async {
      final choice = await showModalBottomSheet<String>(
        context: ctx,
        showDragHandle: true,
        builder: (bs) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final e in _quickReactEmojis)
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => Navigator.of(bs).pop('react:$e'),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(e, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () => Navigator.of(bs).pop('reply'),
              ),
              if (m.authorId == currentUserId && m is TextMessage)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () => Navigator.of(bs).pop('edit'),
                ),
              if (m is TextMessage)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copy'),
                  onTap: () => Navigator.of(bs).pop('copy'),
                ),
            ],
          ),
        ),
      );
      if (choice == null) return;
      if (choice.startsWith('react:')) {
        actions.reactToPeer(
          peer,
          targetStanzaId: m.id,
          emojis: [choice.substring('react:'.length)],
        );
      } else if (choice == 'reply') {
        beginReply(m);
      } else if (choice == 'edit' && m is TextMessage) {
        beginEdit(m);
      } else if (choice == 'copy' && m is TextMessage) {
        await Clipboard.setData(ClipboardData(text: m.text));
      }
    }

    Widget? banner;
    if (editing != null) {
      banner = _EditBanner(preview: previewOf(editing), onCancel: clearBanner);
    } else if (replyingTo != null) {
      banner = _ReplyBanner(
        preview: previewOf(replyingTo),
        onCancel: clearBanner,
      );
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
                textMessageBuilder:
                    (ctx, msg, index, {required isSentByMe, groupStatus}) =>
                        _withReactions(
                          reactions: msg.reactions,
                          isSentByMe: isSentByMe,
                          child: SimpleTextMessage(
                            message: msg,
                            index: index,
                          ),
                        ),
                imageMessageBuilder:
                    (ctx, msg, index, {required isSentByMe, groupStatus}) =>
                        _withReactions(
                          reactions: msg.reactions,
                          isSentByMe: isSentByMe,
                          child: InlineImageBubble(
                            message: msg,
                            isSentByMe: isSentByMe,
                          ),
                        ),
              ),
              onAttachmentTap: () async {
                final picked = await showAttachmentPicker(context);
                if (picked == null) return;
                await actions.sendPeerFile(
                  peer,
                  bytes: picked.bytes,
                  fileName: picked.fileName,
                  mimeType: picked.mimeType,
                );
              },
              onMessageLongPress: onLongPress,
              onMessageSend: (text) {
                final trimmed = text.trim();
                if (trimmed.isEmpty) return;
                if (editing != null) {
                  actions.editPeer(
                    peer,
                    originalStanzaId: editing.id,
                    newBody: trimmed,
                  );
                } else {
                  actions.sendPeer(
                    peer,
                    trimmed,
                    replyToStanzaId: replyingTo?.id,
                  );
                }
                clearBanner();
              },
            ),
          ),
          if (banner != null) banner,
        ],
      ),
    );
  }
}

class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({required this.preview, required this.onCancel});
  final String preview;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.reply, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Replying to: $preview',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditBanner extends StatelessWidget {
  const _EditBanner({required this.preview, required this.onCancel});
  final String preview;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.edit_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Editing: $preview',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps [child] with a small reactions strip below it when [reactions]
/// has any entries. flutter_chat_ui's default renderer ignores
/// `Message.reactions`, so we paint them here.
Widget _withReactions({
  required Map<String, List<String>>? reactions,
  required bool isSentByMe,
  required Widget child,
}) {
  if (reactions == null || reactions.isEmpty) return child;
  return Column(
    crossAxisAlignment: isSentByMe
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      child,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: _ReactionsStrip(reactions: reactions),
      ),
    ],
  );
}

class _ReactionsStrip extends StatelessWidget {
  const _ReactionsStrip({required this.reactions});
  final Map<String, List<String>> reactions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final entry in reactions.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Text(
              entry.value.length > 1
                  ? '${entry.key} ${entry.value.length}'
                  : entry.key,
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}
