import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/active_thread_capsule.dart';
import '../state/capsules/chat_actions_capsule.dart';
import '../state/capsules/config_capsule.dart';
import '../state/capsules/messages_capsule.dart';
import '../state/capsules/unread_capsule.dart';
import 'bubble_chat_page.dart';
import 'bubble_details_page.dart';
import 'chat_widgets.dart';
import 'group_call_banner.dart';
import 'phone_round_button.dart';
import 'responsive.dart';
import 'shared_files_page.dart';
import 'theme_tokens.dart';

/// Full-screen list of a bubble's topics (Google-Groups style). Tapping
/// a topic drills into its own chat; a back button returns here, and
/// another back returns to the bubbles list.
class BubbleTopicsPage extends RearchConsumer {
  const BubbleTopicsPage({super.key, required this.bubble});
  final RainbowBubble bubble;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final config = use(configCapsule);
    final actions = use(chatActionsCapsule);
    final threadKey = '${bubble.id}@muc.${config.xmppDomain}';
    final controller = use(chatControllerCapsule(threadKey));
    final unread = use(unreadCapsule);
    final activeThread = use(activeThreadCapsule);

    // Join the MUC and hydrate this bubble's shared controller once.
    use.effect(() {
      actions.joinMuc(bubble);
      unread.markRead(bubble.id);
      activeThread.value = bubble.id;
      return () {
        if (activeThread.value == bubble.id) activeThread.value = null;
      };
    }, [bubble.id]);

    // Selected topic (wide layout only). On narrow layouts tapping
    // pushes a full-screen chat instead.
    final (sel, setSel) = use
        .state<({String thread, String subject, String? pending})?>(null);
    final effective =
        sel ?? (thread: 'general', subject: 'General', pending: null);

    final palette = phonePaletteOf(context);

    // FAB lives inside the topics column so it never overlaps the
    // composer's send button in the wide-layout chat pane.
    Widget topicsColumn({
      required String? selectedThread,
      required void Function(TopicInfo) onOpenTopic,
      required VoidCallback onNewTopic,
    }) => Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
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
            child: StreamBuilder<ChatOperation>(
              stream: controller.operationsStream,
              builder: (ctx, _) {
                final topics = deriveTopics(controller.messages);
                return ListView.separated(
                  itemCount: topics.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: palette.divider),
                  itemBuilder: (_, i) => _TopicTile(
                    topic: topics[i],
                    selected: topics[i].thread == selectedThread,
                    onTap: () => onOpenTopic(topics[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onNewTopic,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('New topic'),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(bubble.name),
            const Text('Topics', style: TextStyle(fontSize: 12)),
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
      body: Column(
        children: [
          GroupCallBanner(bubble: bubble),
          Expanded(
            // LayoutBuilder (not MediaQuery) so the split reflows live as
            // the window resizes, matching the 1:1 master-detail.
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final wide = constraints.maxWidth >= kWideLayoutBreakpoint;

                void openTopic(TopicInfo t, {bool isNew = false}) {
                  final next = (
                    thread: t.thread,
                    subject: t.subject,
                    pending: isNew ? t.subject : null,
                  );
                  if (wide) {
                    setSel(next);
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BubbleChatPage(
                          bubble: bubble,
                          thread: next.thread,
                          topicSubject: next.subject,
                          pendingSubject: next.pending,
                        ),
                      ),
                    );
                  }
                }

                Future<void> newTopic() async {
                  final subject = await promptNewTopic(context);
                  if (subject == null || subject.trim().isEmpty) return;
                  final id =
                      'topic-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
                  openTopic(
                    TopicInfo(thread: id, subject: subject.trim()),
                    isNew: true,
                  );
                }

                final topicsPane = topicsColumn(
                  selectedThread: wide ? effective.thread : null,
                  onOpenTopic: (t) => openTopic(t),
                  onNewTopic: newTopic,
                );

                if (!wide) return topicsPane;
                return Row(
                  children: [
                    SizedBox(width: 340, child: topicsPane),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: BubbleChatPage(
                        key: ValueKey('${bubble.id}:${effective.thread}'),
                        bubble: bubble,
                        thread: effective.thread,
                        topicSubject: effective.subject,
                        pendingSubject: effective.pending,
                        embedded: true,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    required this.topic,
    required this.onTap,
    this.selected = false,
  });
  final TopicInfo topic;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = phonePaletteOf(context);
    final accent = Theme.of(context).colorScheme.primary;
    final isGeneral = topic.thread == 'general';
    final subtitle = topic.lastText?.trim().isNotEmpty == true
        ? topic.lastText!.trim()
        : (topic.count == 0 ? 'No messages yet' : '${topic.count} messages');
    return ListTile(
      selected: selected,
      selectedTileColor: palette.rowSelected,
      leading: CircleAvatar(
        backgroundColor: palette.avatarBg,
        child: Icon(
          isGeneral ? Icons.forum_outlined : Icons.tag,
          color: accent,
        ),
      ),
      title: Text(
        topic.subject,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: topic.lastAt == null
          ? null
          : Text(
              _shortTime(topic.lastAt!),
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
      onTap: onTap,
    );
  }
}

/// Compact timestamp: HH:mm for today, else day/month.
String _shortTime(DateTime at) {
  final local = at.toLocal();
  final now = DateTime.now();
  final sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  String two(int n) => n.toString().padLeft(2, '0');
  return sameDay
      ? '${two(local.hour)}:${two(local.minute)}'
      : '${local.day}/${local.month}';
}
