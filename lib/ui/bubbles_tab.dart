import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/rainbow_session.dart';
import 'bubble_chat_page.dart';

class BubblesTab extends StatelessWidget {
  const BubblesTab({super.key});

  Future<void> _createBubble(BuildContext context) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New bubble'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      // ignore: use_build_context_synchronously
      await context.read<RainbowSession>().createBubble(controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<RainbowSession>();
    return Scaffold(
      body: s.bubbles.isEmpty
          ? const Center(child: Text('No bubbles yet'))
          : ListView.builder(
              itemCount: s.bubbles.length,
              itemBuilder: (_, i) {
                final b = s.bubbles[i];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.forum)),
                  title: Text(b.name),
                  subtitle: Text(b.topic ?? '${b.members.length} members'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BubbleChatPage(bubble: b),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createBubble(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
