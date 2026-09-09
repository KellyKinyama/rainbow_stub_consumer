import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/rainbow_session.dart';
import 'chat_page.dart';

class ContactsTab extends StatelessWidget {
  const ContactsTab({super.key});

  Color _presenceColor(String? show) {
    switch (show) {
      case 'online':
        return Colors.green;
      case 'away':
        return Colors.orange;
      case 'dnd':
        return Colors.red;
      case 'offline':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<RainbowSession>();
    if (s.roster.isEmpty) {
      return const Center(child: Text('No contacts yet'));
    }
    return RefreshIndicator(
      onRefresh: s.refreshAll,
      child: ListView.builder(
        itemCount: s.roster.length,
        itemBuilder: (_, i) {
          final entry = s.roster[i];
          final live = s.contact(entry.peer.id) ?? entry.peer;
          return ListTile(
            leading: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  child: Text(
                    live.display.isNotEmpty
                        ? live.display[0].toUpperCase()
                        : '?',
                  ),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _presenceColor(live.presenceShow),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ],
            ),
            title: Text(live.display),
            subtitle: Text(
              live.presenceStatus?.isNotEmpty == true
                  ? live.presenceStatus!
                  : live.loginEmail,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => ChatPage(peer: live)),
            ),
          );
        },
      ),
    );
  }
}
