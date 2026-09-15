import 'dart:async';

import 'package:rearch/rearch.dart';

import '../../rainbow/xmpp_client.dart';
import 'xmpp_capsule.dart';

/// A MUC room occupant (XEP-0045), keyed by nick within a room.
class MucOccupant {
  const MucOccupant({
    required this.nick,
    required this.affiliation,
    required this.role,
    this.realJid,
  });

  final String nick;
  final String affiliation;
  final String role;
  final String? realJid;

  bool get isOwner => affiliation == 'owner';

  /// A display label — real bare JID's local part when known, else nick.
  String get label {
    final jid = realJid;
    if (jid == null || jid.isEmpty) return nick;
    final at = jid.indexOf('@');
    return at > 0 ? jid.substring(0, at) : jid;
  }
}

/// Live `roomBareJid → (nick → occupant)` map, driven by
/// [XmppMucOccupant] events. Occupants are added on available presence and
/// dropped on `unavailable`.
Map<String, Map<String, MucOccupant>> mucOccupantsCapsule(CapsuleHandle use) {
  final events = use(xmppEventsCapsule);
  final slot = use.data<Map<String, Map<String, MucOccupant>>>(
    const <String, Map<String, MucOccupant>>{},
  );

  use.effect(() {
    final StreamSubscription<XmppMucOccupant> sub = events
        .where((e) => e is XmppMucOccupant)
        .cast<XmppMucOccupant>()
        .listen((e) {
          final rooms = Map<String, Map<String, MucOccupant>>.from(slot.value);
          final room = Map<String, MucOccupant>.from(
            rooms[e.roomBareJid] ?? const <String, MucOccupant>{},
          );
          if (e.available) {
            room[e.nick] = MucOccupant(
              nick: e.nick,
              affiliation: e.affiliation,
              role: e.role,
              realJid: e.realJid,
            );
          } else {
            room.remove(e.nick);
          }
          rooms[e.roomBareJid] = room;
          slot.value = rooms;
        });
    return sub.cancel;
  }, [events]);

  return slot.value;
}
