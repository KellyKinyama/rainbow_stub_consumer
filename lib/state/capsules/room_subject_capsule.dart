import 'dart:async';

import 'package:rearch/rearch.dart';

import '../../rainbow/xmpp_client.dart';
import 'xmpp_capsule.dart';

/// Live `roomBareJid → subject` map (XEP-0045 §7.2.14), driven by
/// [XmppRoomSubject] events. Empty subjects clear the entry.
Map<String, String> roomSubjectCapsule(CapsuleHandle use) {
  final events = use(xmppEventsCapsule);
  final slot = use.data<Map<String, String>>(const <String, String>{});

  use.effect(() {
    final StreamSubscription<XmppRoomSubject> sub = events
        .where((e) => e is XmppRoomSubject)
        .cast<XmppRoomSubject>()
        .listen((e) {
          final next = Map<String, String>.from(slot.value);
          if (e.subject.isEmpty) {
            next.remove(e.roomBareJid);
          } else {
            next[e.roomBareJid] = e.subject;
          }
          slot.value = next;
        });
    return sub.cancel;
  }, [events]);

  return slot.value;
}
