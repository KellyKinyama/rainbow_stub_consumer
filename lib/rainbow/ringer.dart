import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// A ringer surfaces "there is an incoming call, look at me!" without
/// bundling audio assets — [SystemRinger] delegates to the platform's
/// built-in ringtone, [HapticRinger] is retained as a silent fallback
/// (and default for tests).
abstract class Ringer {
  /// Starts the ring pattern. Idempotent — a second call while
  /// already ringing is a no-op.
  void start();

  /// Stops the pattern immediately. Idempotent.
  void stop();

  /// True while the ringer is currently active.
  bool get isRinging;
}

/// Plays the platform ringtone via `flutter_ringtone_player`. Loops
/// natively — no polling timer needed. Falls back to haptic pulses
/// on platforms where the plugin is a no-op (currently: web on some
/// browsers), so the caller still gets a signal.
class SystemRinger implements Ringer {
  SystemRinger();
  bool _ringing = false;
  Timer? _hapticFallback;

  @override
  bool get isRinging => _ringing;

  @override
  void start() {
    if (_ringing) return;
    _ringing = true;
    try {
      FlutterRingtonePlayer().playRingtone(looping: true);
    } on Object {
      // Plugin unsupported on this platform — quietly fall through
      // to the haptic pulse below.
    }
    HapticFeedback.mediumImpact();
    _hapticFallback = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      HapticFeedback.mediumImpact();
    });
  }

  @override
  void stop() {
    if (!_ringing) return;
    _ringing = false;
    try {
      FlutterRingtonePlayer().stop();
    } on Object {
      // ignored — matches start() best-effort path.
    }
    _hapticFallback?.cancel();
    _hapticFallback = null;
  }
}

/// Test / silent default: fires a haptic pulse every 1500 ms.
class HapticRinger implements Ringer {
  Timer? _timer;

  @override
  bool get isRinging => _timer != null;

  @override
  void start() {
    if (_timer != null) return;
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
