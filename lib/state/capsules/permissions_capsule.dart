import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rearch/rearch.dart';

import 'auth_state_capsule.dart';

/// Snapshot of which runtime permissions have been granted, denied,
/// or not-yet-asked. Consumers can call [ask] to re-request. On web
/// this is always fully granted — the browser prompts for camera /
/// mic per-tab on the first `getUserMedia` call and there is no
/// notification permission we can meaningfully request until the app
/// has a push wire (deferred).
class PermissionsState {
  const PermissionsState({
    required this.camera,
    required this.microphone,
    required this.notifications,
    required this.ask,
  });

  final PermissionSlot camera;
  final PermissionSlot microphone;
  final PermissionSlot notifications;
  final Future<void> Function() ask;

  bool get anyDenied =>
      camera == PermissionSlot.denied ||
      microphone == PermissionSlot.denied ||
      notifications == PermissionSlot.denied;
}

enum PermissionSlot { granted, denied, notAsked, unsupported }

/// Requests camera / microphone / notification permissions
/// automatically the first time the user signs in on this device,
/// then exposes the resulting grant state for any UI that wants to
/// surface a rationale banner.
PermissionsState permissionsCapsule(CapsuleHandle use) {
  final me = use(authCapsule).me;
  final slot = use.data<PermissionsState?>(null);

  Future<void> ask() async {
    if (kIsWeb) {
      slot.value = _webUnsupported(ask);
      return;
    }
    // Request all three in one dialog batch — Android and iOS both
    // batch this into a single OS-level prompt sequence when the
    // requests fire close together.
    final results = await [
      Permission.camera,
      Permission.microphone,
      Permission.notification,
    ].request();
    slot.value = PermissionsState(
      camera: _slot(results[Permission.camera]),
      microphone: _slot(results[Permission.microphone]),
      notifications: _slot(results[Permission.notification]),
      ask: ask,
    );
  }

  use.effect(() {
    if (me == null) {
      slot.value = null;
      return null;
    }
    // Fire-and-forget on sign-in. Any error is swallowed — the
    // permission dialog is best-effort UX, not a blocker.
    ask();
    return null;
  }, [me?.id]);

  return slot.value ??
      PermissionsState(
        camera: PermissionSlot.notAsked,
        microphone: PermissionSlot.notAsked,
        notifications: PermissionSlot.notAsked,
        ask: ask,
      );
}

PermissionSlot _slot(PermissionStatus? s) {
  if (s == null) return PermissionSlot.notAsked;
  if (s.isGranted || s.isLimited) return PermissionSlot.granted;
  if (s.isPermanentlyDenied || s.isDenied || s.isRestricted) {
    return PermissionSlot.denied;
  }
  return PermissionSlot.notAsked;
}

PermissionsState _webUnsupported(Future<void> Function() ask) =>
    PermissionsState(
      camera: PermissionSlot.unsupported,
      microphone: PermissionSlot.unsupported,
      notifications: PermissionSlot.unsupported,
      ask: ask,
    );
