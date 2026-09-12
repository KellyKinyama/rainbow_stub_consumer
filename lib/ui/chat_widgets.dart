import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import 'theme_tokens.dart';

/// Quick-react emoji set shown at the top of the long-press sheet.
const quickReactEmojis = ['👍', '❤️', '😂', '😮', '🎉', '🔥'];

/// Choice returned from [showMessageActions].
sealed class MessageActionChoice {
  const MessageActionChoice();
}

class ReactChoice extends MessageActionChoice {
  const ReactChoice(this.emoji);
  final String emoji;
}

class ReplyChoice extends MessageActionChoice {
  const ReplyChoice();
}

class EditChoice extends MessageActionChoice {
  const EditChoice();
}

class CopyChoice extends MessageActionChoice {
  const CopyChoice();
}

class ForwardChoice extends MessageActionChoice {
  const ForwardChoice();
}

class DeleteChoice extends MessageActionChoice {
  const DeleteChoice();
}

/// Modal bottom sheet with quick-react row + Reply/Edit/Copy/Delete.
/// Edit + Delete surface only for my own text messages.
Future<MessageActionChoice?> showMessageActions(
  BuildContext context, {
  required Message target,
  required String currentUserId,
  required bool allowEdit,
  required bool allowDelete,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (bs) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 8,
              children: [
                for (final e in quickReactEmojis)
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
          if (allowEdit)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.of(bs).pop('edit'),
            ),
          if (target is TextMessage)
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () => Navigator.of(bs).pop('copy'),
            ),
          if (target is TextMessage)
            ListTile(
              leading: const Icon(Icons.forward_outlined),
              title: const Text('Forward'),
              onTap: () => Navigator.of(bs).pop('forward'),
            ),
          if (allowDelete)
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete for everyone',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.of(bs).pop('delete'),
            ),
        ],
      ),
    ),
  );
  if (choice == null) return null;
  if (choice.startsWith('react:')) {
    return ReactChoice(choice.substring('react:'.length));
  }
  return switch (choice) {
    'reply' => const ReplyChoice(),
    'edit' => const EditChoice(),
    'copy' => const CopyChoice(),
    'forward' => const ForwardChoice(),
    'delete' => const DeleteChoice(),
    _ => null,
  };
}

/// Wraps [child] with a reply preview above (if [replyTarget] is
/// non-null) and a reactions strip below (if [reactions] is non-empty).
/// Chips are tappable so the current user can toggle their own reaction.
Widget wrapChatBubble({
  required Message message,
  required bool isSentByMe,
  required String currentUserId,
  required Message? replyTarget,
  required Map<String, List<String>>? reactions,
  required Widget child,
  required void Function(String emoji) onReactionTap,
}) {
  final align = isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
  return Column(
    crossAxisAlignment: align,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (replyTarget != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: _ReplyPreview(target: replyTarget),
        ),
      child,
      if (reactions != null && reactions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: _ReactionsStrip(
            reactions: reactions,
            currentUserId: currentUserId,
            onTap: onReactionTap,
          ),
        ),
    ],
  );
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.target});
  final Message target;

  @override
  Widget build(BuildContext context) {
    final preview = switch (target) {
      TextMessage m => m.text,
      ImageMessage m => '📷 ${m.text ?? 'image'}',
      FileMessage m => '📎 ${m.name}',
      _ => 'message',
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 3,
          ),
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Replying',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ReactionsStrip extends StatelessWidget {
  const _ReactionsStrip({
    required this.reactions,
    required this.currentUserId,
    required this.onTap,
  });
  final Map<String, List<String>> reactions;
  final String currentUserId;
  final void Function(String emoji) onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final entry in reactions.entries)
          _ReactionChip(
            emoji: entry.key,
            reactors: entry.value,
            highlighted: entry.value.contains(currentUserId),
            onTap: () => onTap(entry.key),
          ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.reactors,
    required this.highlighted,
    required this.onTap,
  });
  final String emoji;
  final List<String> reactors;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: highlighted
          ? scheme.primaryContainer
          : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: highlighted ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text(
            reactors.length > 1 ? '$emoji ${reactors.length}' : emoji,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }
}

class ChatReplyBanner extends StatelessWidget {
  const ChatReplyBanner({
    super.key,
    required this.preview,
    required this.onCancel,
  });
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

class ChatEditBanner extends StatelessWidget {
  const ChatEditBanner({
    super.key,
    required this.preview,
    required this.onCancel,
  });
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

/// Preview string used by reply/edit banners.
String previewOfMessage(Message m) => switch (m) {
  TextMessage m => m.text,
  ImageMessage m => '📷 ${m.text ?? 'image'}',
  FileMessage m => '📎 ${m.name}',
  _ => 'message',
};

/// A compact "Load older messages" strip. Renders as a small tappable
/// chip while [canLoadMore] is true; morphs into a spinner while a
/// page is in flight; hides itself once [complete] is true.
class LoadOlderChip extends StatelessWidget {
  const LoadOlderChip({
    super.key,
    required this.canLoadMore,
    required this.isLoading,
    required this.onTap,
  });
  final bool canLoadMore;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!canLoadMore && !isLoading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : ActionChip(
                avatar: const Icon(Icons.history, size: 18),
                label: const Text('Load older messages'),
                onPressed: onTap,
              ),
      ),
    );
  }
}

class PhoneTextBubble extends StatelessWidget {
  const PhoneTextBubble({
    super.key,
    required this.message,
    required this.isSentByMe,
  });

  final TextMessage message;
  final bool isSentByMe;

  @override
  Widget build(BuildContext context) {
    final palette = phonePaletteOf(context);
    final bg = isSentByMe ? palette.ourBubble : palette.theirBubble;
    final radius = const Radius.circular(PhoneTokens.bubbleRadius);
    final tail = const Radius.circular(2);
    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width *
              PhoneTokens.bubbleMaxWidthFactor,
        ),
        child: Container(
          margin: EdgeInsets.only(
            top: 4,
            bottom: 2,
            left: isSentByMe ? 40 : 8,
            right: isSentByMe ? 8 : 40,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: radius,
              topRight: radius,
              bottomLeft: isSentByMe ? radius : tail,
              bottomRight: isSentByMe ? tail : radius,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 2,
                offset: Offset(1, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.text,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: PhoneTokens.titleFontSize,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatTime(message.createdAt),
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: PhoneTokens.timeStampFontSize,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime? d) {
    final t = d ?? DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}
