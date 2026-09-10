import 'dart:async';

import 'package:rearch/rearch.dart';

import '../../rainbow/xmpp_client.dart';
import '../models/presence.dart';
import 'xmpp_capsule.dart';

/// Live map of `bareJid → Presence`, driven by [XmppPresenceUpdate] events
/// on the XMPP stream. Rebuilds every time the map changes.
Map<String, Presence> presenceCapsule(CapsuleHandle use) {
  final events = use(xmppEventsCapsule);
  final slot = use.data<Map<String, Presence>>(const <String, Presence>{});

  use.effect(() {
    final StreamSubscription<XmppPresenceUpdate> sub = events
        .where((e) => e is XmppPresenceUpdate)
        .cast<XmppPresenceUpdate>()
        .listen((e) {
          slot.value = <String, Presence>{
            ...slot.value,
            e.fromBare: Presence(show: e.show, status: e.status),
          };
        });
    return sub.cancel;
  }, [events]);

  return slot.value;
}
