import 'package:rearch/rearch.dart';

import '../models/auth_state.dart';
import 'auth_state_capsule.dart';
import 'messages_capsule.dart';
import 'rest_capsule.dart';
import 'xmpp_capsule.dart';

/// Controller returned by [authControllerCapsule].
class AuthController {
  const AuthController({
    required this.state,
    required this.signIn,
    required this.signOut,
  });

  final AuthState state;
  final Future<void> Function(String email, String password) signIn;
  final Future<void> Function() signOut;
}

/// Orchestrates REST login + XMPP connect, and flips [authStateCapsule].
///
/// Kept as an idempotent controller (rebuilds don't re-trigger login) so
/// UI code can call `use(authControllerCapsule).signIn(...)` without
/// worrying about how many times its parent rebuilt.
AuthController authControllerCapsule(CapsuleHandle use) {
  final rest = use(restCapsule);
  final xmpp = use(xmppCapsule);
  final authSlot = use(authStateCapsule);

  Future<void> signIn(String email, String password) async {
    final result = await rest.login(email, password);
    rest.setBearer(result.token);
    await xmpp.connect(email: email, saslPassword: result.token);
    authSlot.value = AuthState.signedIn(
      me: result.loggedInUser,
      token: result.token,
    );
  }

  Future<void> signOut() async {
    try {
      await xmpp.disconnect();
    } catch (_) {
      // best-effort teardown; underlying socket may already be closed.
    }
    try {
      await rest.logout();
    } catch (_) {
      // ditto — server may already have invalidated the session.
    }
    rest.setBearer(null);
    // Drop per-thread chat controllers + MAM cursors so the next signed-in
    // user builds fresh capsules and re-queries MAM.
    resetMessagesCapsuleCache();
    authSlot.value = const AuthState.signedOut();
  }

  return AuthController(
    state: authSlot.value,
    signIn: signIn,
    signOut: signOut,
  );
}
