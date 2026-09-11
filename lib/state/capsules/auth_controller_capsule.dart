import 'dart:async';

import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import '../../rainbow/xmpp_client.dart';
import '../models/auth_state.dart';
import '../session_store.dart';
import 'auth_state_capsule.dart';
import 'messages_capsule.dart';
import 'push_capsule.dart';
import 'rest_capsule.dart';
import 'session_store_capsule.dart';
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
  final push = use(pushCapsule);
  final store = use(sessionStoreCapsule);
  final booted = use.data<bool>(false);

  Future<void> restore() async {
    authSlot.value = const AuthState.checking();
    try {
      final stored = await store.read();
      if (stored == null) {
        // Only clobber back to signedOut if nothing else (signIn) has
        // taken over during our async work.
        if (authSlot.value is Checking) {
          authSlot.value = const AuthState.signedOut();
        }
        return;
      }
      rest.setBearer(stored.token);
      final me = await rest.getUser(stored.userId);
      await xmpp.connect(email: stored.email, saslPassword: stored.token);
      if (authSlot.value is Checking) {
        authSlot.value = AuthState.signedIn(me: me, token: stored.token);
      }
    } on Object {
      rest.setBearer(null);
      await store.clear();
      if (authSlot.value is Checking) {
        authSlot.value = const AuthState.signedOut();
      }
    }
  }

  // One-shot silent re-auth on cold start.
  use.effect(() {
    if (!booted.value) {
      scheduleMicrotask(() {
        booted.value = true;
        unawaited(restore());
      });
    }
    return null;
  }, const []);

  // Silent auto-reconnect: when the XMPP WebSocket drops while the
  // user is still signed in, prefer XEP-0198 resume; fall back to a
  // full connect. Exponential backoff avoids reconnect storms if
  // the stub is genuinely down.
  use.effect(() {
    Timer? timer;
    var attempt = 0;

    Future<void> tryReconnect() async {
      final state = authSlot.value;
      if (state is! SignedIn) return;
      try {
        if (xmpp.canResume) {
          await xmpp.resume(
            email: state.me.loginEmail,
            saslPassword: state.token,
          );
        } else {
          await xmpp.connect(
            email: state.me.loginEmail,
            saslPassword: state.token,
          );
        }
        attempt = 0;
      } on Object {
        // Failed \u2014 XmppDisconnected fires again from onDone/onError;
        // that path will re-schedule with a larger backoff.
      }
    }

    final sub = xmpp.events.listen((e) {
      switch (e) {
        case XmppConnected():
          attempt = 0;
          timer?.cancel();
          timer = null;
        case XmppDisconnected():
          if (authSlot.value is! SignedIn) return;
          if (timer != null) return;
          final delayMs = 500 * (1 << (attempt.clamp(0, 5)));
          attempt++;
          timer = Timer(Duration(milliseconds: delayMs), () {
            timer = null;
            tryReconnect();
          });
      }
    });

    return () {
      timer?.cancel();
      sub.cancel();
    };
  }, [xmpp]);

  Future<void> signIn(String email, String password) async {
    final result = await rest.login(email, password);
    rest.setBearer(result.token);
    await xmpp.connect(email: email, saslPassword: result.token);
    authSlot.value = AuthState.signedIn(
      me: result.loggedInUser,
      token: result.token,
    );
    // Persist so a page refresh / app relaunch skips the login form.
    unawaited(
      store.write(
        StoredSession(
          email: email,
          token: result.token,
          userId: result.loggedInUser.id,
        ),
      ),
    );
  }

  Future<void> signOut() async {
    // Ordering matters: delete the push token FIRST while the bearer
    // is still valid server-side, then close the XMPP socket, then
    // hit rest.logout() which invalidates the token, then flip the
    // slot and drop the local bearer.
    final currentUserId = authSlot.value.me?.id;
    final currentPushToken = push.token;
    if (currentUserId != null && currentPushToken != null) {
      try {
        await rest.deletePushToken(
          userId: currentUserId,
          token: currentPushToken,
        );
      } catch (_) {
        // Best-effort; the token may already be gone server-side.
      }
    }
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
    resetMessagesCapsuleCache();
    authSlot.value = const AuthState.signedOut();
    rest.setBearer(null);
    unawaited(store.clear());
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
