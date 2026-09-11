import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
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
    required this.refreshMe,
    required this.updateMe,
  });

  final AuthState state;
  final Future<void> Function(String email, String password) signIn;
  final Future<void> Function() signOut;

  /// Re-fetches `/users/:id` for the signed-in user and hot-swaps
  /// [authStateCapsule] with the updated `me` — useful after a
  /// profile edit, avatar upload, or presence change.
  final Future<RainbowUser?> Function() refreshMe;

  /// Applies a profile edit via `PUT /users/:id` and refreshes the
  /// local slot in one step. Returns the updated user on success.
  final Future<RainbowUser?> Function({
    String? firstName,
    String? lastName,
    String? nickName,
    String? title,
    String? jobTitle,
    String? language,
  })
  updateMe;
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

  Future<RainbowUser?> refreshMe() async {
    final current = authSlot.value;
    if (current is! SignedIn) return null;
    try {
      final fresh = await rest.getUser(current.me.id);
      authSlot.value = AuthState.signedIn(me: fresh, token: current.token);
      return fresh;
    } on Object {
      return null;
    }
  }

  Future<RainbowUser?> updateMe({
    String? firstName,
    String? lastName,
    String? nickName,
    String? title,
    String? jobTitle,
    String? language,
  }) async {
    final current = authSlot.value;
    if (current is! SignedIn) return null;
    final updated = await rest.updateMe(
      userId: current.me.id,
      firstName: firstName,
      lastName: lastName,
      nickName: nickName,
      title: title,
      jobTitle: jobTitle,
      language: language,
    );
    authSlot.value = AuthState.signedIn(me: updated, token: current.token);
    return updated;
  }

  return AuthController(
    state: authSlot.value,
    signIn: signIn,
    signOut: signOut,
    refreshMe: refreshMe,
    updateMe: updateMe,
  );
}
