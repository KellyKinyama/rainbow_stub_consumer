import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import 'auth_state_capsule.dart';
import 'rest_capsule.dart';

class BubblesRefresher {
  const BubblesRefresher(this.version, this.bump);
  final int version;
  final void Function() bump;
}

BubblesRefresher bubblesRefresherCapsule(CapsuleHandle use) {
  final (v, setV) = use.state<int>(0);
  return BubblesRefresher(v, () => setV(v + 1));
}

/// The signed-in user's bubbles (rooms). Same shape as [rosterCapsule].
AsyncValue<List<RainbowBubble>> bubblesCapsule(CapsuleHandle use) {
  final auth = use(authCapsule);
  final rest = use(restCapsule);
  final refresher = use(bubblesRefresherCapsule);

  final future = use.memo<Future<List<RainbowBubble>>>(
    () => auth.isSignedIn ? rest.rooms() : Future.value(const []),
    [auth, refresher.version],
  );
  return use.future(future);
}
