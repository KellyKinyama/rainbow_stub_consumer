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
    final (query, setQuery) = use.state<String>('');
    final normalized = query.toLowerCase().trim();
    bool matches(RainbowUser u) {
      if (normalized.isEmpty) return true;
      return u.display.toLowerCase().contains(normalized) ||
          u.loginEmail.toLowerCase().contains(normalized);
    }

    Widget list;
    switch (rosterAsync) {
      case AsyncLoading<List<RosterEntry>>():
        list = const Center(child: CircularProgressIndicator());
      case AsyncError<List<RosterEntry>>(:final error):
        list = Center(child: Text('Roster failed: $error'));
      case AsyncData<List<RosterEntry>>(:final data):
        final filtered = data
            .where((e) => matches(e.peer))
            .toList(growable: false);
        if (data.isEmpty) {
          list = const Center(child: Text('No contacts yet'));
        } else if (filtered.isEmpty) {
          list = Center(
            child: Text(
              'No match for "$query"',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        } else {
          list = ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final entry = filtered[i];
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
                        color: _presenceColor(
                          livePresence?.show ?? live.presenceShow,
                        ),
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
          );
        }
    }

    return Column(
      children: [
        _SearchField(hint: 'Search contacts', onChanged: setQuery),
        Expanded(child: list),
      ],
    );
  }

  // Presence capsule keys by bare JID; the roster carries only user id, so
  // check both `id@domain` variants (peer JIDs and localhost/prod).
  static Presence? _presenceFor(RainbowUser u, Map<String, Presence> map) {
    for (final key in map.keys) {
      final local = key.contains('@')
          ? key.substring(0, key.indexOf('@'))
          : key;
      if (local == u.id) return map[key];
    }
    return null;
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search),
          hintText: hint,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          filled: true,
        ),
      ),
    );
  }
}
