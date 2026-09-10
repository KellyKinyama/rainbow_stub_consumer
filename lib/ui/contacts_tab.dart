import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/presence_capsule.dart';
import '../state/capsules/roster_capsule.dart';
import '../state/models/presence.dart';
import 'chat_page.dart';

class ContactsTab extends RearchConsumer {
  const ContactsTab({super.key});

  static Color _presenceColor(String? show) {
    switch (show) {
      case 'chat':
      case 'online':
        return Colors.green;
      case 'away':
        return Colors.orange;
      case 'dnd':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final rosterAsync = use(rosterCapsule);
    final presence = use(presenceCapsule);

    return switch (rosterAsync) {
      AsyncLoading<List<RosterEntry>>() => const Center(
        child: CircularProgressIndicator(),
      ),
      AsyncError<List<RosterEntry>>(:final error) => Center(
        child: Text('Roster failed: $error'),
      ),
      AsyncData<List<RosterEntry>>(data: final roster) when roster.isEmpty =>
        const Center(child: Text('No contacts yet')),
      AsyncData<List<RosterEntry>>(data: final roster) => ListView.builder(
        itemCount: roster.length,
        itemBuilder: (_, i) {
          final entry = roster[i];
          final live = entry.peer;
          final livePresence = _presenceFor(live, presence);
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
                    color: _presenceColor(livePresence?.show ?? live.presenceShow),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ],
            ),
            title: Text(live.display),
            subtitle: Text(
              livePresence?.status?.isNotEmpty == true
                  ? livePresence!.status!
                  : (live.presenceStatus?.isNotEmpty == true
                        ? live.presenceStatus!
                        : live.loginEmail),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => ChatPage(peer: live)),
            ),
          );
        },
      ),
    };
  }

  // Presence capsule keys by bare JID; the roster carries only user id, so
  // check both `id@domain` variants (peer JIDs and localhost/prod).
  static Presence? _presenceFor(RainbowUser u, Map<String, Presence> map) {
    for (final key in map.keys) {
      final local = key.contains('@') ? key.substring(0, key.indexOf('@')) : key;
      if (local == u.id) return map[key];
    }
    return null;
  }
}
