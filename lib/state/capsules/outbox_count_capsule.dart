import 'dart:async';

import 'package:rearch/rearch.dart';

import '../../rainbow/xmpp_client.dart';
import 'auth_state_capsule.dart';
import 'outgoing_queue_capsule.dart';
import 'xmpp_capsule.dart';

/// Reactive count of pending sends in the [OutgoingQueue] for the
/// current user. Refreshes on XmppConnected (the drain completed) and
/// on user sign-in.
int outboxCountCapsule(CapsuleHandle use) {
  final xmpp = use(xmppCapsule);
  final events = use(xmppEventsCapsule);
  final outbox = use(outgoingQueueCapsule);
  final myId = use(authCapsule).me?.id;
  final slot = use.data<int>(0);

  Future<void> refresh() async {
    if (myId == null) {
      slot.value = 0;
      return;
    }
    final rows = await outbox.readAll(myId);
    slot.value = rows.length;
  }

  use.effect(() {
    if (myId == null) {
      slot.value = 0;
      return null;
    }
    unawaited(refresh());
    final connectedSub = events
        .where((e) => e is XmppConnected)
        .listen((_) => refresh());
    // Poll on a slow interval to catch new sends the local capsule
    // hasn't observed (the write happens outside this capsule's scope).
    final timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
    return () {
      connectedSub.cancel();
      timer.cancel();
    };
  }, [outbox, xmpp, myId]);

  return slot.value;
}
