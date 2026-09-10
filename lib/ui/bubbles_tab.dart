import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/bubbles_capsule.dart';
import '../state/capsules/chat_actions_capsule.dart';
import 'bubble_chat_page.dart';

class BubblesTab extends RearchConsumer {
  const BubblesTab({super.key});

  Future<void> _createBubble(BuildContext context, ChatActions actions) async {
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
      await actions.createBubble(controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final bubblesAsync = use(bubblesCapsule);
    final actions = use(chatActionsCapsule);

    final body = switch (bubblesAsync) {
      AsyncLoading<List<RainbowBubble>>() => const Center(
        child: CircularProgressIndicator(),
      ),
      AsyncError<List<RainbowBubble>>(:final error) => Center(
        child: Text('Bubbles failed: $error'),
      ),
      AsyncData<List<RainbowBubble>>(data: final list) when list.isEmpty =>
        const Center(child: Text('No bubbles yet')),
      AsyncData<List<RainbowBubble>>(data: final list) => ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) {
          final b = list[i];
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
    };

    return Scaffold(
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createBubble(context, actions),
        child: const Icon(Icons.add),
      ),
    );
  }
}
