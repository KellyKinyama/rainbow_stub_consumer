import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/auth_state_capsule.dart';
import '../state/capsules/call_manager_capsule.dart';
import '../state/capsules/chat_actions_capsule.dart';
import '../state/capsules/config_capsule.dart';
import '../state/capsules/messages_capsule.dart';
import 'attachment_picker.dart';
import 'chat_widgets.dart';
import 'forward_picker.dart';

class ChatPage extends RearchConsumer {
  const ChatPage({super.key, required this.peer});
  final RainbowUser peer;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final config = use(configCapsule);
    final actions = use(chatActionsCapsule);
    final callManager = use(callManagerCapsule);
    final me = use(authCapsule).me;
    final threadKey = '${peer.id}@${config.xmppDomain}';
    final controller = use(chatControllerCapsule(threadKey));
    final peerIsTyping = use(typingCapsule(threadKey));
    final input = use.textEditingController();
    final (replyingTo, setReplyingTo) = use.state<Message?>(null);
    final (editing, setEditing) = use.state<TextMessage?>(null);

    final currentUserId = me?.id ?? 'me';
    final selfName = me?.display ?? me?.loginEmail ?? 'Me';

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

    Message? lookupTarget(String? id) {
      if (id == null) return null;
      for (final m in controller.messages) {
        if (m.id == id) return m;
      }
      return null;
    }

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

    void toggleMyReaction(Message target, String emoji) {
      final current = _reactionsOf(target);
      final myEmojis = <String>{
        for (final e in current.entries)
          if (e.value.contains(currentUserId)) e.key,
      };
      if (myEmojis.contains(emoji)) {
        myEmojis.remove(emoji);
      } else {
        myEmojis.add(emoji);
      }
      actions.reactToPeer(
        peer,
        targetStanzaId: target.id,
        emojis: myEmojis.toList(),
      );
    }

    Future<void> onLongPress(
      BuildContext ctx,
      Message m, {
      required int index,
      required LongPressStartDetails details,
    }) async {
      final isMine = m.authorId == currentUserId;
      final choice = await showMessageActions(
        ctx,
        target: m,
        currentUserId: currentUserId,
        allowEdit: isMine && m is TextMessage,
        allowDelete: isMine,
      );
      if (choice == null) return;
      switch (choice) {
        case ReactChoice(:final emoji):
          toggleMyReaction(m, emoji);
        case ReplyChoice():
          beginReply(m);
        case EditChoice() when m is TextMessage:
          beginEdit(m);
        case CopyChoice() when m is TextMessage:
          await Clipboard.setData(ClipboardData(text: m.text));
        case ForwardChoice() when m is TextMessage:
          final target = await pickForwardTarget(ctx);
          if (target == null) return;
          switch (target) {
            case ForwardPeerTarget(:final peer):
              actions.sendPeer(peer, m.text);
            case ForwardBubbleTarget(:final bubble):
              actions.sendGroup(bubble, m.text);
          }
        case DeleteChoice():
          actions.retractPeer(peer, targetStanzaId: m.id);
        default:
          break;
      }
    }

    Widget? banner;
    if (editing != null) {
      banner = ChatEditBanner(
        preview: previewOfMessage(editing),
        onCancel: clearBanner,
      );
    } else if (replyingTo != null) {
      banner = ChatReplyBanner(
        preview: previewOfMessage(replyingTo),
        onCancel: clearBanner,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(peer.display),
        actions: [
          IconButton(
            tooltip: 'Voice call',
            icon: const Icon(Icons.call),
            onPressed: () => callManager.startCall(
              peer: peer,
              // M-3 targets the peer's bare JID; a real deployment
              // would pick a specific resource. The stub's Jingle
              // router accepts either.
              peerFullJid: threadKey,
            ),
          ),
          IconButton(
            tooltip: 'Video call',
            icon: const Icon(Icons.videocam),
            onPressed: () => callManager.startCall(
              peer: peer,
              peerFullJid: threadKey,
              video: true,
            ),
          ),
        ],
      ),
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
          ListenableBuilder(
            listenable: mamPageStateOf(threadKey),
            builder: (ctx, _) {
              final s = mamPageStateOf(threadKey);
              return LoadOlderChip(
                canLoadMore: s.canLoadMore,
                isLoading: s.isLoading,
                onTap: () => actions.loadOlder(threadKey),
              );
            },
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                final m = n.metrics;
                if (m.axis == Axis.vertical &&
                    m.pixels >= m.maxScrollExtent - 200) {
                  actions.loadOlder(threadKey);
                }
                return false;
              },
              child: Chat(
                currentUserId: currentUserId,
                resolveUser: resolveUser,
                chatController: controller,
                builders: Builders(
                  composerBuilder: (ctx) =>
                      Composer(textEditingController: input),
                  textMessageBuilder:
                      (ctx, msg, index, {required isSentByMe, groupStatus}) =>
                          wrapChatBubble(
                            message: msg,
                            isSentByMe: isSentByMe,
                            currentUserId: currentUserId,
                            replyTarget: lookupTarget(msg.replyToMessageId),
                            reactions: msg.reactions,
                            onReactionTap: (e) => toggleMyReaction(msg, e),
                            child: SimpleTextMessage(
                              message: msg,
                              index: index,
                            ),
                          ),
                  imageMessageBuilder:
                      (ctx, msg, index, {required isSentByMe, groupStatus}) =>
                          wrapChatBubble(
                            message: msg,
                            isSentByMe: isSentByMe,
                            currentUserId: currentUserId,
                            replyTarget: lookupTarget(msg.replyToMessageId),
                            reactions: msg.reactions,
                            onReactionTap: (e) => toggleMyReaction(msg, e),
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
          ),
          if (banner != null) banner,
        ],
      ),
    );
  }
}

Map<String, List<String>> _reactionsOf(Message m) => switch (m) {
  TextMessage m => Map.of(m.reactions ?? const {}),
  ImageMessage m => Map.of(m.reactions ?? const {}),
  FileMessage m => Map.of(m.reactions ?? const {}),
  _ => <String, List<String>>{},
};
