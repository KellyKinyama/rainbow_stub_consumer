import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import 'auth_state_capsule.dart';
import 'rest_capsule.dart';

/// Live list of bubbles the signed-in user has been invited to but
/// hasn't accepted or declined yet. Fires an initial fetch on
/// sign-in; the returned controller exposes [refresh] so UI can pull
/// after accept / decline / new invitation events.
class BubbleInvitationsController {
  const BubbleInvitationsController({
    required this.entries,
    required this.refresh,
  });

  final AsyncValue<List<RainbowBubble>> entries;
  final Future<void> Function() refresh;
}

BubbleInvitationsController bubbleInvitationsCapsule(CapsuleHandle use) {
  final rest = use(restCapsule);
  final me = use(authCapsule).me;
  final slot = use.data<AsyncValue<List<RainbowBubble>>>(
    const AsyncLoading<List<RainbowBubble>>(None()),
  );

  Option<List<RainbowBubble>> previousOf(AsyncValue<List<RainbowBubble>> v) =>
      switch (v) {
        AsyncData<List<RainbowBubble>>(:final data) => Some(data),
        AsyncLoading<List<RainbowBubble>>(:final previousData) => previousData,
        AsyncError<List<RainbowBubble>>(:final previousData) => previousData,
      };

  Future<void> load() async {
    if (me == null) {
      slot.value = const AsyncData<List<RainbowBubble>>(<RainbowBubble>[]);
      return;
    }
    slot.value = AsyncLoading<List<RainbowBubble>>(previousOf(slot.value));
    try {
      final list = await rest.roomInvitations();
      slot.value = AsyncData<List<RainbowBubble>>(list);
    } on Object catch (e, s) {
      slot.value =
          AsyncError<List<RainbowBubble>>(e, s, previousOf(slot.value));
    }
  }

  use.effect(() {
    load();
    return null;
  }, [me?.id]);

  return BubbleInvitationsController(entries: slot.value, refresh: load);
}
