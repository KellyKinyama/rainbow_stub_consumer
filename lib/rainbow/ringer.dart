import 'dart:async';

import 'package:flutter/services.dart';

/// A ringer surfaces "there is an incoming call, look at me!" without
/// bundling audio assets — M-4 ships a haptic-only ringer for
/// simplicity; M-6 can swap in a proper audio impl (`audioplayers`
/// or `just_audio` with a bundled ringtone) behind the same
/// interface.
abstract class Ringer {
  /// Starts the ring pattern. Idempotent — a second call while
  /// already ringing is a no-op.
  void start();

  /// Stops the pattern immediately. Idempotent.
  void stop();

  /// True while the ringer is currently active.
  bool get isRinging;
}

/// Default ringer: fires a haptic pulse every 1500 ms. Silent on
/// desktop platforms where `HapticFeedback` is a no-op — that is
/// tolerated by design (users will still see the [CallOverlay]).
class HapticRinger implements Ringer {
  Timer? _timer;

  @override
  bool get isRinging => _timer != null;

  @override
  void start() {
    if (_timer != null) return;
    // Fire an immediate pulse so the user feels it right away, then
    // repeat on a slow cadence.
    HapticFeedback.mediumImpact();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      HapticFeedback.mediumImpact();
    });
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
