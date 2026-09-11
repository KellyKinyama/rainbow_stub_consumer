import '_web_ringer_io.dart'
    if (dart.library.html) '_web_ringer_web.dart'
    if (dart.library.js_interop) '_web_ringer_web.dart';

/// Starts a looping tone using the platform's Web Audio API on
/// browsers; no-op everywhere else. Called by [SystemRinger] to
/// cover the case where `flutter_ringtone_player` isn't wired to
/// a native ringtone (all current web browsers).
void startWebRing() => platformStartWebRing();

/// Stops the tone started by [startWebRing]. Idempotent.
void stopWebRing() => platformStopWebRing();
