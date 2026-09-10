import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import 'auth_state_capsule.dart';
import 'rest_capsule.dart';

/// The signed-in user's bubbles (rooms). Same shape as [rosterCapsule].
AsyncValue<List<RainbowBubble>> bubblesCapsule(CapsuleHandle use) {
  final auth = use(authCapsule);
  final rest = use(restCapsule);

  final future = use.memo<Future<List<RainbowBubble>>>(
    () => auth.isSignedIn ? rest.rooms() : Future.value(const []),
    [auth],
  );
  return use.future(future);
}
