import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';

import '../state/capsules/muc_occupants_capsule.dart';

/// Live list of the occupants in [roomJid], borrowed from xmpp-web's
/// RoomOccupants panel. Driven by MUC presence (XEP-0045).
class RoomOccupantsSheet extends RearchConsumer {
  const RoomOccupantsSheet({super.key, required this.roomJid});

  final String roomJid;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final rooms = use(mucOccupantsCapsule);
    final occupants = (rooms[roomJid]?.values.toList() ?? <MucOccupant>[])
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.people_outline, size: 20),
                const SizedBox(width: 8),
                Text(
                  'In this room · ${occupants.length}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
          if (occupants.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No occupants yet'),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in occupants)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        child: Text(
                          o.label.isNotEmpty ? o.label[0].toUpperCase() : '?',
                        ),
                      ),
                      title: Text(o.label),
                      subtitle: Text(o.role),
                      trailing: o.isOwner
                          ? const Icon(Icons.star, size: 16)
                          : null,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

void showRoomOccupants(BuildContext context, String roomJid) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => RoomOccupantsSheet(roomJid: roomJid),
  );
}
