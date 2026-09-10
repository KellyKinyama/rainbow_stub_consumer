import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import 'auth_state_capsule.dart';
import 'rest_capsule.dart';

/// The signed-in user's roster (networks). Fetches lazily when auth flips
/// to signed-in, resets when signed out.
///
/// Returns [AsyncValue] so consumers can render loading / error / data
/// states uniformly.
AsyncValue<List<RosterEntry>> rosterCapsule(CapsuleHandle use) {
  final auth = use(authCapsule);
  final rest = use(restCapsule);

  final future = use.memo<Future<List<RosterEntry>>>(
    () => auth.isSignedIn ? rest.networks() : Future.value(const []),
    [auth],
  );
  return use.future(future);
}
