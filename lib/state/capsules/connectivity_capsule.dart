import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:rearch/rearch.dart';

/// True while the device has *any* usable network path (wifi / mobile
/// / vpn / ethernet). False when explicitly offline. Emits an initial
/// value synchronously from the last known result so a fresh mount
/// doesn't flash a wrong banner.
bool connectivityCapsule(CapsuleHandle use) {
  final slot = use.data<bool>(true);
  use.effect(() {
    final connectivity = Connectivity();

    void apply(List<ConnectivityResult> results) {
      slot.value = results.any((r) => r != ConnectivityResult.none);
    }

    // Seed with the current status so the banner isn't stale on mount.
    unawaited(connectivity.checkConnectivity().then(apply));

    final StreamSubscription<List<ConnectivityResult>> sub = connectivity
        .onConnectivityChanged
        .listen(apply);
    return sub.cancel;
  }, const []);
  return slot.value;
}
