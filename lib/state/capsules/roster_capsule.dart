import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import 'auth_state_capsule.dart';
import 'rest_capsule.dart';

class RosterRefresher {
  const RosterRefresher(this.version, this.bump);
  final int version;
  final void Function() bump;
}

/// Version-counter side channel that lets non-capsule code (e.g.
/// `ChatActions.addContact`) invalidate the roster cache.
RosterRefresher rosterRefresherCapsule(CapsuleHandle use) {
  final (v, setV) = use.state<int>(0);
  return RosterRefresher(v, () => setV(v + 1));
}

/// The signed-in user's roster (networks). Fetches lazily when auth flips
/// to signed-in, resets when signed out.
///
/// Returns [AsyncValue] so consumers can render loading / error / data
/// states uniformly.
AsyncValue<List<RosterEntry>> rosterCapsule(CapsuleHandle use) {
  final auth = use(authCapsule);
  final rest = use(restCapsule);
  final refresher = use(rosterRefresherCapsule);

  final future = use.memo<Future<List<RosterEntry>>>(
    () => auth.isSignedIn ? rest.networks() : Future.value(const []),
    [auth, refresher.version],
  );
  return use.future(future);
}
