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
import '../state/capsules/active_thread_capsule.dart';
import '../state/capsules/presence_capsule.dart';
import '../state/capsules/unread_capsule.dart';
import '../state/capsules/xmpp_capsule.dart';
import '../state/models/presence.dart';
import 'attachment_picker.dart';
import 'chat_widgets.dart';
import 'forward_picker.dart';
import 'phone_round_button.dart';
import 'shared_files_page.dart';
import 'theme_tokens.dart';

class ChatPage extends RearchConsumer {
  const ChatPage({super.key, required this.peer});
  final RainbowUser peer;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final config = use(configCapsule);
    final actions = use(chatActionsCapsule);
    final callManager = use(callManagerCapsule);
    final xmpp = use(xmppCapsule);
    final me = use(authCapsule).me;
    final threadKey = '${peer.id}@${config.xmppDomain}';
    final controller = use(chatControllerCapsule(threadKey));
    final peerIsTyping = use(typingCapsule(threadKey));
    final presence = use(presenceCapsule);
    final activeThread = use(activeThreadCapsule);
    final unread = use(unreadCapsule);
    final input = use.textEditingController();
    final scrollCtrl = use.memo(() => ScrollController(), const []);
    use.effect(() => scrollCtrl.dispose, const []);
    final (replyingTo, setReplyingTo) = use.state<Message?>(null);
    final (editing, setEditing) = use.state<TextMessage?>(null);

    final currentUserId = me?.id ?? 'me';
    final selfName = me?.display ?? me?.loginEmail ?? 'Me';

    // Clear unread badge for this peer once the page is open.
    use.effect(() {
      unread.markRead(peer.id);
      activeThread.value = peer.id;
      return () {
        if (activeThread.value == peer.id) activeThread.value = null;
      };
    }, [peer.id]);

    // Probe the peer's presence on open so the header shows a fresh
    // online/offline state even if we missed the last broadcast.
    use.effect(() {
      xmpp.probePresence(threadKey);
      return null;
    }, [threadKey]);

    final peerShow = _presenceFor(peer, presence)?.show ?? peer.presenceShow;
    final peerOnline = peerShow == 'online' || peerShow == 'chat';
    final (lastSeen, setLastSeen) = use.state<DateTime?>(null);

    // When the peer is offline, fetch XEP-0012 last activity for the
    // "last seen …" header line.
    use.effect(() {
      if (peerOnline) {
        setLastSeen(null);
      } else {
        xmpp.queryLastActivity(threadKey).then((d) {
          if (d != null) setLastSeen(DateTime.now().subtract(d));
        });
      }
      return null;
    }, [threadKey, peerOnline]);

    // Follow new messages: scroll to the bottom when a message is
    // appended — always for our own send, and for an incoming message
    // when already near the bottom (so reading history isn't yanked).
    use.effect(() {
      final sub = controller.operationsStream.listen((op) {
        if (op.type != ChatOperationType.insert) return;
        final idx = op.index;
        if (idx == null || idx < controller.messages.length - 1) return;
        final mine = op.message?.authorId == currentUserId;
        // Delay past the insert animation so maxScrollExtent is final.
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          if (!scrollCtrl.hasClients) return;
          final pos = scrollCtrl.position;
          final nearBottom = pos.maxScrollExtent - pos.pixels < 600;
          if (mine || nearBottom) {
            scrollCtrl.animateTo(
              pos.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      });
      return sub.cancel;
    }, [controller]);

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
      backgroundColor: phonePaletteOf(context).chatWallpaper,
      appBar: AppBar(
        title: _PeerHeader(
          peer: peer,
          presence: _presenceFor(peer, presence),
          isTyping: peerIsTyping,
          lastSeen: lastSeen,
        ),
        actions: [
          PhoneRoundButton(
            tooltip: 'Voice call',
            icon: Icons.call_rounded,
            onPressed: () =>
                callManager.startCall(peer: peer, peerFullJid: threadKey),
          ),
          PhoneRoundButton(
            tooltip: 'Video call',
            icon: Icons.videocam_rounded,
            onPressed: () => callManager.startCall(
              peer: peer,
              peerFullJid: threadKey,
              video: true,
            ),
          ),
          PhoneRoundButton(
            tooltip: 'Shared files',
            icon: Icons.folder_open,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    SharedFilesPage(peerJid: threadKey, title: peer.display),
              ),
            ),
          ),
          const SizedBox(width: 4),
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
                  chatAnimatedListBuilder: (context, itemBuilder) =>
                      ChatAnimatedList(
                        itemBuilder: itemBuilder,
                        scrollController: scrollCtrl,
                      ),
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
                            child: PhoneTextBubble(
                              message: msg,
                              isSentByMe: isSentByMe,
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

class _PeerHeader extends StatelessWidget {
  const _PeerHeader({
    required this.peer,
    required this.presence,
    required this.isTyping,
    this.lastSeen,
  });

  final RainbowUser peer;
  final Presence? presence;
  final bool isTyping;
  final DateTime? lastSeen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final show = presence?.show ?? peer.presenceShow;
    final online = show == 'online' || show == 'chat';
    final String subtitle;
    if (isTyping) {
      subtitle = 'typing…';
    } else if (online) {
      subtitle = 'online';
    } else if (lastSeen != null) {
      subtitle = _lastSeenLabel(lastSeen!);
    } else {
      subtitle = _presenceLabel(presence, peer);
    }
    final highlight = isTyping || online;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(peer.display, overflow: TextOverflow.ellipsis, maxLines: 1),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
              color: highlight
                  ? PhoneTokens.callActive
                  : scheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
      ],
    );
  }
}

String _lastSeenLabel(DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return 'last seen just now';
  if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes} min ago';
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(t.year, t.month, t.day);
  final hm =
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
  if (that == today) return 'last seen today at $hm';
  if (that == today.subtract(const Duration(days: 1))) {
    return 'last seen yesterday at $hm';
  }
  return 'last seen ${t.day}/${t.month} at $hm';
}

Presence? _presenceFor(RainbowUser u, Map<String, Presence> map) {
  for (final key in map.keys) {
    final local = key.contains('@') ? key.substring(0, key.indexOf('@')) : key;
    if (local == u.id) return map[key];
  }
  return null;
}

String _presenceLabel(Presence? p, RainbowUser u) {
  final show = p?.show ?? u.presenceShow;
  final status = p?.status ?? u.presenceStatus;
  final label = switch (show) {
    'chat' || 'online' => 'online',
    'away' => 'away',
    'dnd' => 'do not disturb',
    'xa' => 'extended away',
    _ => 'offline',
  };
  if (status != null && status.isNotEmpty) return '$label · $status';
  return label;
}
