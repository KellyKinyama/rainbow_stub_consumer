import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

import '_web_ringer.dart';

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

/// Plays the platform ringtone on mobile (`flutter_ringtone_player`),
/// falls back to a Web Audio beep loop on browsers, and pulses haptic
/// feedback in parallel on any platform that supports it.
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
    if (kIsWeb) {
      startWebRing();
    } else {
      try {
        FlutterRingtonePlayer().playRingtone(looping: true);
      } on Object {
        // Plugin unsupported on this platform — silently fall through.
      }
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
    if (kIsWeb) {
      stopWebRing();
    } else {
      try {
        FlutterRingtonePlayer().stop();
      } on Object {
        // ignored — matches start() best-effort path.
      }
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
