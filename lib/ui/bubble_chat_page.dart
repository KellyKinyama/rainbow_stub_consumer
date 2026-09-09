import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../rainbow/models.dart';
import '../state/rainbow_session.dart';

class BubbleChatPage extends StatefulWidget {
  const BubbleChatPage({super.key, required this.bubble});
  final RainbowBubble bubble;
  @override
  State<BubbleChatPage> createState() => _BubbleChatPageState();
}

class _BubbleChatPageState extends State<BubbleChatPage> {
  final _controller = TextEditingController();
  bool _joined = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _join());
  }

  void _join() {
    final s = context.read<RainbowSession>();
    final room = '${widget.bubble.id}@muc.${s.config.xmppDomain}';
    final nick = s.me?.id ?? 'me';
    s.xmpp.joinMuc(room, nick);
    setState(() => _joined = true);
  }

  String get _threadKey =>
      '${widget.bubble.id}@muc.${context.read<RainbowSession>().config.xmppDomain}';

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    context.read<RainbowSession>().sendGroupChatTo(widget.bubble, text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<RainbowSession>();
    final msgs = session.thread(_threadKey);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.bubble.name),
            if (widget.bubble.topic != null)
              Text(widget.bubble.topic!, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!_joined) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final m = msgs[i];
                final sender = _extractSender(m.from);
                return Align(
                  alignment: m.isMine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.7,
                    ),
                    decoration: BoxDecoration(
                      color: m.isMine
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!m.isMine)
                          Text(
                            sender,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        Text(m.body),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Send to room…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(icon: const Icon(Icons.send), onPressed: _send),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _extractSender(String jid) {
    final slash = jid.indexOf('/');
    if (slash >= 0) return jid.substring(slash + 1);
    return jid;
  }
}
