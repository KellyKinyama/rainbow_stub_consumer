import 'package:flutter/material.dart';

/// A small curated emoji set for the composer picker — grouped visually
/// (smileys, gestures, hearts, common objects). Kept dependency-free.
const List<String> composerEmojis = [
  '😀',
  '😃',
  '😄',
  '😁',
  '😆',
  '😅',
  '😂',
  '🤣',
  '😊',
  '😇',
  '🙂',
  '🙃',
  '😉',
  '😌',
  '😍',
  '🥰',
  '😘',
  '😗',
  '😜',
  '🤪',
  '🤨',
  '🧐',
  '🤓',
  '😎',
  '🥳',
  '😏',
  '😞',
  '😔',
  '😟',
  '😕',
  '🙁',
  '☹️',
  '😣',
  '😖',
  '😫',
  '😭',
  '😤',
  '😡',
  '🤬',
  '🤯',
  '😳',
  '🥵',
  '🥶',
  '😱',
  '😨',
  '😰',
  '😥',
  '🤔',
  '🤗',
  '🤭',
  '🤫',
  '😴',
  '🤤',
  '😪',
  '😵',
  '🤐',
  '🥴',
  '🤢',
  '🤮',
  '🤧',
  '😷',
  '🤒',
  '🤕',
  '🥱',
  '👍',
  '👎',
  '👌',
  '✌️',
  '🤞',
  '🤟',
  '🤘',
  '👏',
  '🙌',
  '👐',
  '🙏',
  '💪',
  '👋',
  '🤝',
  '✍️',
  '💅',
  '❤️',
  '🧡',
  '💛',
  '💚',
  '💙',
  '💜',
  '🖤',
  '🤍',
  '💔',
  '❣️',
  '💕',
  '💞',
  '💯',
  '🔥',
  '⭐',
  '✨',
  '🎉',
  '🎊',
  '🎁',
  '🏆',
  '👀',
  '💬',
  '✅',
  '❌',
  '☕',
  '🍺',
  '🍕',
  '🎂',
  '🚀',
  '💡',
  '📎',
  '📌',
];

/// Inserts [emoji] into [controller] at the caret (replacing any current
/// selection) and advances the caret past it. Testable without a widget.
void insertEmoji(TextEditingController controller, String emoji) {
  final value = controller.value;
  final sel = value.selection;
  if (!sel.isValid) {
    final next = value.text + emoji;
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    return;
  }
  final next = value.text.replaceRange(sel.start, sel.end, emoji);
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: sel.start + emoji.length),
  );
}

/// Shows a modal bottom-sheet emoji grid; resolves to the tapped emoji or
/// null if dismissed.
Future<String?> showEmojiPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (bs) => SafeArea(
      child: SizedBox(
        height: 280,
        child: GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 44,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: composerEmojis.length,
          itemBuilder: (ctx, i) {
            final e = composerEmojis[i];
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.of(bs).pop(e),
              child: Center(
                child: Text(e, style: const TextStyle(fontSize: 24)),
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// Left-aligned emoji button for the composer's `topWidget` slot. Opens
/// [showEmojiPicker] and inserts the choice into [controller].
class EmojiComposerButton extends StatelessWidget {
  const EmojiComposerButton({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.emoji_emotions_outlined),
        tooltip: 'Emoji',
        onPressed: () async {
          final emoji = await showEmojiPicker(context);
          if (emoji != null) insertEmoji(controller, emoji);
        },
      ),
    );
  }
}
