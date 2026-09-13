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
import '../state/capsules/roster_capsule.dart';
import '../state/capsules/active_thread_capsule.dart';
import '../state/capsules/unread_capsule.dart';
import 'attachment_picker.dart';
import 'chat_widgets.dart';
import 'chat_wallpaper.dart';
import 'bubble_details_page.dart';
import 'forward_picker.dart';
import 'group_call_banner.dart';
import 'phone_round_button.dart';
import 'shared_files_page.dart';
import 'theme_tokens.dart';

class BubbleChatPage extends RearchConsumer {
  const BubbleChatPage({
    super.key,
    required this.bubble,
    this.thread = 'general',
    this.topicSubject,
    this.pendingSubject,
    this.embedded = false,
  });
  final RainbowBubble bubble;

  /// The XEP-0201 thread this view is scoped to; 'general' holds
  /// untagged messages.
  final String thread;

  /// Display title for the topic; falls back to the bubble name.
  final String? topicSubject;

  /// Non-null only for a freshly created topic — its subject rides the
  /// first message sent, then is cleared.
  final String? pendingSubject;

  /// When shown inside a two-pane group layout, suppresses the AppBar
  /// back button (the surrounding page owns navigation).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final config = use(configCapsule);
    final actions = use(chatActionsCapsule);
    final me = use(authCapsule).me;
    final rosterAsync = use(rosterCapsule);
    final threadKey = '${bubble.id}@muc.${config.xmppDomain}';
    final controller = use(chatControllerCapsule(threadKey));
    final unread = use(unreadCapsule);
    final activeThread = use(activeThreadCapsule);
    final input = use.textEditingController();
    final (replyingTo, setReplyingTo) = use.state<Message?>(null);
    final (editing, setEditing) = use.state<TextMessage?>(null);

    // Join the MUC once per bubble.
    use.effect(() {
      actions.joinMuc(bubble);
      unread.markRead(bubble.id);
      activeThread.value = bubble.id;
      return () {
        if (activeThread.value == bubble.id) activeThread.value = null;
      };
    }, [bubble.id]);

    // This view is scoped to a single topic (XEP-0201 thread). The
    // pending subject rides only the first message of a brand-new topic.
    final (pendingSubject, setPendingSubject) = use.state<String?>(
      this.pendingSubject,
    );

    // A controller scoped to this topic — mirrors only this thread's
    // messages from the bubble's shared controller.
    final topicController = use.memo(() => InMemoryChatController(), const []);
    use.effect(() => topicController.dispose, const []);
    use.effect(() {
      void sync() {
        final filtered = controller.messages
            .where((m) => _threadOf(m) == thread)
            .toList();
        topicController.setMessages(filtered);
      }

      sync();
      final sub = controller.operationsStream.listen((_) => sync());
      return sub.cancel;
    }, [controller, thread]);

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
      for (final m in bubble.members) {
        if (m.userId == id) return User(id: id, name: id);
      }
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
      actions.reactToGroup(
        bubble,
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
          actions.retractGroup(bubble, targetStanzaId: m.id);
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
        automaticallyImplyLeading: !embedded,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(topicSubject ?? bubble.name),
            Text(
              topicSubject == null ? 'General' : bubble.name,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          PhoneRoundButton(
            tooltip: 'Shared files',
            icon: Icons.folder_open,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    SharedFilesPage(peerJid: threadKey, title: bubble.name),
              ),
            ),
          ),
          PhoneRoundButton(
            tooltip: 'Bubble details',
            icon: Icons.info_outline,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BubbleDetailsPage(bubble: bubble),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ChatWallpaper(
        child: Column(
          children: [
            GroupCallBanner(bubble: bubble),
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
                  chatController: topicController,
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
                    await actions.sendGroupFile(
                      bubble,
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
                      actions.editGroup(
                        bubble,
                        originalStanzaId: editing.id,
                        newBody: trimmed,
                      );
                    } else {
                      actions.sendGroup(
                        bubble,
                        trimmed,
                        replyToStanzaId: replyingTo?.id,
                        thread: thread,
                        subject: pendingSubject,
                      );
                      // The subject only rides the topic's first message.
                      if (pendingSubject != null) setPendingSubject(null);
                    }
                    clearBanner();
                  },
                ),
              ),
            ),
            if (banner != null) banner,
          ],
        ),
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

/// The topic (XEP-0201 thread) a message belongs to; untagged → general.
String _threadOf(Message m) => (m.metadata?['thread'] as String?) ?? 'general';

/// Aggregated info for one topic in a bubble.
class TopicInfo {
  TopicInfo({required this.thread, required this.subject});
  final String thread;
  String subject;
  DateTime? lastAt;
  String? lastText;
  int count = 0;
}

/// Groups a bubble's messages into topics by thread; "General" always
/// leads. Subject comes from the message that opened the topic.
List<TopicInfo> deriveTopics(List<Message> msgs) {
  final map = <String, TopicInfo>{
    'general': TopicInfo(thread: 'general', subject: 'General'),
  };
  for (final m in msgs) {
    final thread = (m.metadata?['thread'] as String?) ?? 'general';
    final subject = m.metadata?['subject'] as String?;
    final t = map.putIfAbsent(
      thread,
      () => TopicInfo(thread: thread, subject: subject ?? 'Topic'),
    );
    if (subject != null && subject.isNotEmpty) t.subject = subject;
    final at = m.createdAt;
    if (at != null && (t.lastAt == null || at.isAfter(t.lastAt!))) {
      t.lastAt = at;
      t.lastText = switch (m) {
        TextMessage tm => tm.text,
        ImageMessage _ => '📷 Photo',
        FileMessage _ => '📎 Attachment',
        _ => null,
      };
    }
    t.count++;
  }
  final list = map.values.toList()
    ..sort((a, b) {
      if (a.thread == 'general') return -1;
      if (b.thread == 'general') return 1;
      final al = a.lastAt, bl = b.lastAt;
      if (al == null && bl == null) return 0;
      if (al == null) return 1;
      if (bl == null) return -1;
      return bl.compareTo(al);
    });
  return list;
}

Future<String?> promptNewTopic(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: const Text('New topic'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Topic subject'),
        onSubmitted: (v) => Navigator.of(dctx).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dctx).pop(ctrl.text),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}
