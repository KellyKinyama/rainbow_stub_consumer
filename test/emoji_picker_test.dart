// Composer emoji insertion — borrowed from xmpp-web's EmojiPicker.vue.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/ui/emoji_picker.dart';

void main() {
  group('insertEmoji', () {
    test('appends to an empty field and moves the caret to the end', () {
      final c = TextEditingController();
      insertEmoji(c, '🎉');
      expect(c.text, '🎉');
      expect(c.selection.baseOffset, '🎉'.length);
    });

    test('inserts at the caret within existing text', () {
      final c = TextEditingController(text: 'ab');
      c.selection = const TextSelection.collapsed(offset: 1);
      insertEmoji(c, '🔥');
      expect(c.text, 'a🔥b');
      expect(c.selection.baseOffset, 1 + '🔥'.length);
    });

    test('replaces the current selection', () {
      final c = TextEditingController(text: 'hello');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      insertEmoji(c, '👍');
      expect(c.text, '👍');
      expect(c.selection.baseOffset, '👍'.length);
    });

    test('appends when the selection is invalid (never focused)', () {
      final c = TextEditingController(text: 'hi ');
      insertEmoji(c, '😀');
      expect(c.text, 'hi 😀');
      expect(c.selection.baseOffset, 'hi 😀'.length);
    });
  });
}
