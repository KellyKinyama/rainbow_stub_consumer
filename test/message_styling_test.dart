// XEP-0393 inline styling parser — borrowed from xmpp-web's Message.vue
// grammar (bold/italic/strike/code + auto-links).
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/ui/message_styling.dart';

void main() {
  group('parseMessageStyle', () {
    test('plain text is a single text run', () {
      expect(parseMessageStyle('hello world'), [
        const StyledRun(StyledRunKind.text, 'hello world'),
      ]);
    });

    test('bold / italic / strike / code markers', () {
      expect(parseMessageStyle('*bold*'), [
        const StyledRun(StyledRunKind.bold, 'bold'),
      ]);
      expect(parseMessageStyle('_it_'), [
        const StyledRun(StyledRunKind.italic, 'it'),
      ]);
      expect(parseMessageStyle('~no~'), [
        const StyledRun(StyledRunKind.strike, 'no'),
      ]);
      expect(parseMessageStyle('`x = 1`'), [
        const StyledRun(StyledRunKind.code, 'x = 1'),
      ]);
    });

    test('mixed text, style and link', () {
      final runs = parseMessageStyle('see *this* at https://a.b/c.');
      expect(runs, [
        const StyledRun(StyledRunKind.text, 'see '),
        const StyledRun(StyledRunKind.bold, 'this'),
        const StyledRun(StyledRunKind.text, ' at '),
        const StyledRun(
          StyledRunKind.link,
          'https://a.b/c',
          href: 'https://a.b/c',
        ),
        const StyledRun(StyledRunKind.text, '.'),
      ]);
    });

    test('mid-word underscores stay literal (no false italic)', () {
      expect(parseMessageStyle('my_file_name.txt'), [
        const StyledRun(StyledRunKind.text, 'my_file_name.txt'),
      ]);
    });

    test('whitespace-edged content is not a style span', () {
      // "a * b * c" must not bold " b ".
      expect(parseMessageStyle('a * b * c'), [
        const StyledRun(StyledRunKind.text, 'a * b * c'),
      ]);
    });

    test('empty marker pair is literal', () {
      expect(parseMessageStyle('**'), [
        const StyledRun(StyledRunKind.text, '**'),
      ]);
    });

    test('mailto links are detected', () {
      final runs = parseMessageStyle('ping mailto:x@y.z now');
      expect(runs, [
        const StyledRun(StyledRunKind.text, 'ping '),
        const StyledRun(
          StyledRunKind.link,
          'mailto:x@y.z',
          href: 'mailto:x@y.z',
        ),
        const StyledRun(StyledRunKind.text, ' now'),
      ]);
    });

    test('code content keeps its inner spaces and symbols', () {
      expect(parseMessageStyle('`a *b* _c_`'), [
        const StyledRun(StyledRunKind.code, 'a *b* _c_'),
      ]);
    });
  });
}
