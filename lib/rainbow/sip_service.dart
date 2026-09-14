import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';

/// User-entered SIP account + WebSocket transport settings for the dialer.
@immutable
class SipCreds {
  const SipCreds({
    required this.wsUrl,
    required this.aor,
    required this.authUser,
    required this.password,
    required this.displayName,
  });

  /// SIP-over-WebSocket URL, e.g. `wss://sip.example.com:8089/ws`.
  final String wsUrl;

  /// Address of record, e.g. `sip:1001@example.com`.
  final String aor;
  final String authUser;
  final String password;
  final String displayName;

  bool get isComplete => wsUrl.isNotEmpty && aor.isNotEmpty;

  /// Domain parsed from the AOR (`sip:user@domain` → `domain`).
  String get domain {
    final at = aor.indexOf('@');
    if (at < 0) return '';
    return aor.substring(at + 1);
  }

  SipCreds copyWith({
    String? wsUrl,
    String? aor,
    String? authUser,
    String? password,
    String? displayName,
  }) => SipCreds(
    wsUrl: wsUrl ?? this.wsUrl,
    aor: aor ?? this.aor,
    authUser: authUser ?? this.authUser,
    password: password ?? this.password,
    displayName: displayName ?? this.displayName,
  );

  static const empty = SipCreds(
    wsUrl: '',
    aor: '',
    authUser: '',
    password: '',
    displayName: '',
  );
}

/// Persists [SipCreds] locally (SharedPreferences). The password is stored
/// as typed by the user; this is a demo dialer, not a secrets vault.
class SipSettingsStore {
  const SipSettingsStore();

  static const _kWs = 'sip.wsUrl';
  static const _kAor = 'sip.aor';
  static const _kUser = 'sip.authUser';
  static const _kPass = 'sip.password';
  static const _kName = 'sip.displayName';

  Future<SipCreds> load() async {
    final p = await SharedPreferences.getInstance();
    return SipCreds(
      wsUrl: p.getString(_kWs) ?? '',
      aor: p.getString(_kAor) ?? '',
      authUser: p.getString(_kUser) ?? '',
      password: p.getString(_kPass) ?? '',
      displayName: p.getString(_kName) ?? '',
    );
  }

  Future<void> save(SipCreds c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kWs, c.wsUrl);
    await p.setString(_kAor, c.aor);
    await p.setString(_kUser, c.authUser);
    await p.setString(_kPass, c.password);
    await p.setString(_kName, c.displayName);
  }
}

/// Wraps [SIPUAHelper] and exposes the registration + call state as a
/// [ChangeNotifier] the UI can watch. Handles a single active call
/// (the dialer is a one-line softphone).
class SipService extends ChangeNotifier implements SipUaHelperListener {
  final SIPUAHelper helper = SIPUAHelper();

  SipCreds _creds = SipCreds.empty;
  bool _started = false;

  RegistrationStateEnum registerState = RegistrationStateEnum.NONE;
  TransportStateEnum? transportState;

  Call? activeCall;
  CallStateEnum callState = CallStateEnum.NONE;
  MediaStream? remoteStream;
  bool muted = false;
  bool held = false;
  String? lastError;

  bool get isRegistered => registerState == RegistrationStateEnum.REGISTERED;
  bool get hasActiveCall => activeCall != null;
  bool get isIncoming =>
      activeCall?.direction == Direction.incoming &&
      callState != CallStateEnum.CONFIRMED &&
      callState != CallStateEnum.ACCEPTED;

  /// (Re)connect and register with [creds].
  void connect(SipCreds creds) {
    _creds = creds;
    if (_started) {
      helper.removeSipUaHelperListener(this);
      helper.stop();
      _started = false;
    }
    helper.addSipUaHelperListener(this);

    final settings = UaSettings()
      ..webSocketUrl = creds.wsUrl
      ..webSocketSettings.allowBadCertificate = true
      ..webSocketSettings.extraHeaders = <String, dynamic>{}
      ..transportType = TransportType.WS
      ..uri = creds.aor
      ..authorizationUser = creds.authUser.isEmpty ? null : creds.authUser
      ..password = creds.password.isEmpty ? null : creds.password
      ..displayName = creds.displayName.isEmpty ? null : creds.displayName
      ..userAgent = 'Rainbow Dialer'
      ..dtmfMode = DtmfMode.RFC2833
      ..register = true;

    helper.start(settings);
    _started = true;
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (!_started) return;
    helper.removeSipUaHelperListener(this);
    helper.stop();
    _started = false;
    registerState = RegistrationStateEnum.NONE;
    notifyListeners();
  }

  /// Dials [number]. A bare number/extension is expanded to
  /// `sip:<number>@<domain>` using the registered account's domain.
  Future<bool> dial(String number) async {
    final n = number.trim();
    if (n.isEmpty) return false;
    final target = n.contains('@')
        ? (n.startsWith('sip:') ? n : 'sip:$n')
        : 'sip:$n@${_creds.domain}';
    lastError = null;
    return helper.call(target, voiceOnly: true);
  }

  void answer() {
    final c = activeCall;
    if (c == null) return;
    c.answer(helper.buildCallOptions(true));
  }

  void hangup() {
    final c = activeCall;
    if (c == null) return;
    if (callState == CallStateEnum.ENDED) return;
    // sip_ua's Call.hangup() iterates peerConnection.getLocalStreams()/
    // getRemoteStreams() and `return`s on the first null entry — which is
    // exactly what flutter_webrtc returns on web — so it bails before
    // sending BYE. Terminate the RTCSession directly to guarantee teardown.
    try {
      c.session.terminate();
    } catch (e) {
      lastError = e.toString();
    }
  }

  void sendDtmf(String tone) {
    activeCall?.sendDTMF(tone);
  }

  void toggleMute() {
    final c = activeCall;
    if (c == null) return;
    if (muted) {
      c.unmute(true, false);
    } else {
      c.mute(true, false);
    }
    muted = !muted;
    notifyListeners();
  }

  void toggleHold() {
    final c = activeCall;
    if (c == null) return;
    if (held) {
      c.unhold();
    } else {
      c.hold();
    }
    held = !held;
    notifyListeners();
  }

  void _resetCall() {
    activeCall = null;
    callState = CallStateEnum.NONE;
    remoteStream = null;
    muted = false;
    held = false;
  }

  // --- SipUaHelperListener ---

  @override
  void registrationStateChanged(RegistrationState state) {
    registerState = state.state ?? RegistrationStateEnum.NONE;
    if (state.state == RegistrationStateEnum.REGISTRATION_FAILED) {
      lastError = state.cause?.cause?.toString() ?? 'Registration failed';
    }
    notifyListeners();
  }

  @override
  void transportStateChanged(TransportState state) {
    transportState = state.state;
    notifyListeners();
  }

  @override
  void callStateChanged(Call call, CallState state) {
    activeCall = call;
    callState = state.state;
    switch (state.state) {
      case CallStateEnum.STREAM:
        if (state.originator == Originator.remote && state.stream != null) {
          remoteStream = state.stream;
        }
      case CallStateEnum.FAILED:
        lastError = state.cause?.cause?.toString() ?? 'Call failed';
        _resetCall();
      case CallStateEnum.ENDED:
        _resetCall();
      default:
        break;
    }
    notifyListeners();
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}

  @override
  void onNewInfo(SipInfo info) {}

  @override
  void dispose() {
    if (_started) {
      helper.removeSipUaHelperListener(this);
      helper.stop();
    }
    super.dispose();
  }
}
