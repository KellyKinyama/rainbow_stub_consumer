import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:rearch/rearch.dart';

import 'auth_state_capsule.dart';
import 'rest_capsule.dart';

/// Result surfaced to any UI that wants to observe registration state.
enum PushRegistrationStatus { idle, registering, registered, failed }

class PushRegistration {
  const PushRegistration({
    required this.status,
    this.token,
    this.platform,
    this.error,
  });
  final PushRegistrationStatus status;
  final String? token;
  final String? platform;
  final String? error;
}

/// On each successful login, registers a per-process fake device token
/// with the stub's `POST /users/:id/push-tokens` endpoint. In production
/// this token would come from FCM / APNs. For the stub it's a random
/// 32-char hex string; the intent is only to exercise the wire and
/// prove the "would-push" server hook fires while the user is offline.
PushRegistration pushCapsule(CapsuleHandle use) {
  final me = use(authCapsule).me;
  final rest = use(restCapsule);
  final slot = use.data<PushRegistration>(
    const PushRegistration(status: PushRegistrationStatus.idle),
  );

  use.effect(() {
    if (me == null) {
      slot.value = const PushRegistration(status: PushRegistrationStatus.idle);
      return null;
    }
    final token = _generateFakeToken();
    final platform = _platform();
    slot.value = PushRegistration(
      status: PushRegistrationStatus.registering,
      token: token,
      platform: platform,
    );
    unawaited(() async {
      try {
        await rest.registerPushToken(
          userId: me.id,
          token: token,
          platform: platform,
        );
        slot.value = PushRegistration(
          status: PushRegistrationStatus.registered,
          token: token,
          platform: platform,
        );
      } on Exception catch (e) {
        slot.value = PushRegistration(
          status: PushRegistrationStatus.failed,
          token: token,
          platform: platform,
          error: e.toString(),
        );
      }
    }());
    // Cleanup is the auth controller's job during signOut: it needs to
    // await the DELETE before rest.logout() invalidates the bearer
    // server-side. See authControllerCapsule.signOut.
    return null;
  }, [me?.id, rest]);

  return slot.value;
}

String _generateFakeToken() {
  final r = Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < 32; i++) {
    buf.write(r.nextInt(16).toRadixString(16));
  }
  return buf.toString();
}

String _platform() {
  if (kIsWeb) return 'web';
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  return 'debug';
}
