import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The kind of a parsed styling run (XEP-0393 subset + auto-links).
enum StyledRunKind { text, bold, italic, strike, code, link }

/// A contiguous run of message text with a single style applied.
class StyledRun {
  const StyledRun(this.kind, this.text, {this.href});
  final StyledRunKind kind;
  final String text;

  /// Target URL for [StyledRunKind.link] runs, otherwise null.
  final String? href;

  @override
  bool operator ==(Object other) =>
      other is StyledRun &&
      other.kind == kind &&
      other.text == text &&
      other.href == href;

  @override
  int get hashCode => Object.hash(kind, text, href);

  @override
  String toString() => 'StyledRun($kind, "$text"${href != null ? ', $href' : ''})';
}

final _linkRe = RegExp(
  r'(?:https?://|mailto:)[^\s]+',
  caseSensitive: false,
);
const _openBoundary = ' \n\t([{<"\'';
const _closeBoundary = ' \n\t.,;:!?)]}>"\'';
const _trailingTrim = '.,;:!?)]}>"\'';

/// Parses a message body into styled runs following the common XEP-0393
/// inline grammar: `*bold*`, `_italic_`, `~strike~`, `` `code` `` and
/// bare http(s)/mailto links. Styling markers only fire at word
/// boundaries with non-whitespace-edged content, so mid-word underscores
/// (e.g. `my_file_name`) and arithmetic (`a * b`) stay literal. Nesting
/// is not applied — the first matched span wins.
List<StyledRun> parseMessageStyle(String input) {
  final runs = <StyledRun>[];
  final buf = StringBuffer();
  final n = input.length;
  var i = 0;

  void flushText() {
    if (buf.isEmpty) return;
    _emitTextWithLinks(buf.toString(), runs);
    buf.clear();
  }

  bool tryCode() {
    final close = input.indexOf('`', i + 1);
    if (close <= i + 1) return false;
    final content = input.substring(i + 1, close);
    if (content.contains('\n')) return false;
    flushText();
    runs.add(StyledRun(StyledRunKind.code, content));
    i = close + 1;
    return true;
  }

  bool tryStyle(String marker, StyledRunKind kind) {
    if (i > 0 && !_openBoundary.contains(input[i - 1])) return false;
    final close = input.indexOf(marker, i + 1);
    if (close <= i + 1) return false;
    final content = input.substring(i + 1, close);
    if (content.contains('\n')) return false;
    if (content.startsWith(' ') || content.endsWith(' ')) return false;
    if (close + 1 < n && !_closeBoundary.contains(input[close + 1])) {
      return false;
    }
    flushText();
    runs.add(StyledRun(kind, content));
    i = close + 1;
    return true;
  }

  while (i < n) {
    final c = input[i];
    if (c == '`' && tryCode()) continue;
    if (c == '*' && tryStyle('*', StyledRunKind.bold)) continue;
    if (c == '_' && tryStyle('_', StyledRunKind.italic)) continue;
    if (c == '~' && tryStyle('~', StyledRunKind.strike)) continue;
    buf.write(c);
    i++;
  }
  flushText();
  return runs;
}

void _emitTextWithLinks(String text, List<StyledRun> runs) {
  var last = 0;
  for (final m in _linkRe.allMatches(text)) {
    if (m.start > last) {
      runs.add(StyledRun(StyledRunKind.text, text.substring(last, m.start)));
    }
    var url = m.group(0)!;
    // Trailing sentence punctuation is almost never part of the URL.
    while (url.isNotEmpty && _trailingTrim.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    runs.add(StyledRun(StyledRunKind.link, url, href: url));
    last = m.start + url.length;
  }
  if (last < text.length) {
    runs.add(StyledRun(StyledRunKind.text, text.substring(last)));
  }
}

/// Renders a message body with XEP-0393 inline styling and tappable
/// links. Moderation tombstones (metadata `moderated`) render as muted
/// italics without any styling applied.
class StyledMessageText extends StatefulWidget {
  const StyledMessageText({
    super.key,
    required this.text,
    required this.baseStyle,
    this.moderated = false,
  });

  final String text;
  final TextStyle baseStyle;
  final bool moderated;

  @override
  State<StyledMessageText> createState() => _StyledMessageTextState();
}

class _StyledMessageTextState extends State<StyledMessageText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    if (widget.moderated) {
      return Text(
        widget.text,
        style: widget.baseStyle.copyWith(fontStyle: FontStyle.italic),
      );
    }

    final linkColor = Theme.of(context).colorScheme.primary;
    final spans = <InlineSpan>[];
    for (final run in parseMessageStyle(widget.text)) {
      switch (run.kind) {
        case StyledRunKind.text:
          spans.add(TextSpan(text: run.text));
        case StyledRunKind.bold:
          spans.add(
            TextSpan(
              text: run.text,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        case StyledRunKind.italic:
          spans.add(
            TextSpan(
              text: run.text,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          );
        case StyledRunKind.strike:
          spans.add(
            TextSpan(
              text: run.text,
              style: const TextStyle(decoration: TextDecoration.lineThrough),
            ),
          );
        case StyledRunKind.code:
          spans.add(
            TextSpan(
              text: run.text,
              style: const TextStyle(
                fontFamily: 'monospace',
                backgroundColor: Color(0x14000000),
              ),
            ),
          );
        case StyledRunKind.link:
          final rec = TapGestureRecognizer()..onTap = () => _open(run.href!);
          _recognizers.add(rec);
          spans.add(
            TextSpan(
              text: run.text,
              style: TextStyle(
                color: linkColor,
                decoration: TextDecoration.underline,
              ),
              recognizer: rec,
            ),
          );
      }
    }
    return Text.rich(TextSpan(style: widget.baseStyle, children: spans));
  }
}
