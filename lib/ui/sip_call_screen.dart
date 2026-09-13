import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sip_ua/sip_ua.dart';

import '../rainbow/sip_service.dart';
import 'dial_pad.dart';

/// Full-screen in-call UI for the SIP dialer. Rendered by the dialer
/// while [SipService.hasActiveCall] is true. Owns the WebRTC renderer
/// used to route remote audio.
class SipCallScreen extends StatefulWidget {
  const SipCallScreen({super.key, required this.service});
  final SipService service;

  @override
  State<SipCallScreen> createState() => _SipCallScreenState();
}

class _SipCallScreenState extends State<SipCallScreen> {
  final RTCVideoRenderer _remote = RTCVideoRenderer();
  bool _rendererReady = false;
  bool _showDtmf = false;
  DateTime? _connectedAt;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _remote.initialize().then((_) {
      if (!mounted) return;
      setState(() => _rendererReady = true);
      _attachStream();
    });
    // Ticks the in-call duration label once per second.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _connectedAt != null) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant SipCallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _attachStream();
  }

  void _attachStream() {
    if (!_rendererReady) return;
    final stream = widget.service.remoteStream;
    if (_remote.srcObject != stream) {
      _remote.srcObject = stream;
    }
    if (widget.service.callState == CallStateEnum.CONFIRMED &&
        _connectedAt == null) {
      _connectedAt = DateTime.now();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _remote.srcObject = null;
    _remote.dispose();
    super.dispose();
  }

  String _title() {
    final id = widget.service.activeCall?.remote_identity;
    if (id == null || id.isEmpty) return 'Unknown';
    return _displayFromSip(id);
  }

  /// Extracts a friendly label from a SIP identity string, which may be a
  /// name-addr (`"Bob" <sip:bob@x>`) or a bare URI (`sip:bob@x`).
  static String _displayFromSip(String identity) {
    var s = identity.trim();
    final lt = s.indexOf('<');
    if (lt >= 0) {
      final gt = s.indexOf('>', lt);
      s = gt > lt ? s.substring(lt + 1, gt) : s.substring(lt + 1);
    }
    s = s.replaceFirst('sips:', '').replaceFirst('sip:', '');
    final at = s.indexOf('@');
    if (at > 0) s = s.substring(0, at);
    return s.isEmpty ? identity : s;
  }

  String _status() {
    switch (widget.service.callState) {
      case CallStateEnum.CALL_INITIATION:
      case CallStateEnum.CONNECTING:
        return 'Calling…';
      case CallStateEnum.PROGRESS:
        return 'Ringing…';
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
      case CallStateEnum.STREAM:
      case CallStateEnum.UNMUTED:
      case CallStateEnum.MUTED:
      case CallStateEnum.HOLD:
      case CallStateEnum.UNHOLD:
        return widget.service.isIncoming ? 'Incoming call' : 'In call';
      case CallStateEnum.FAILED:
        return 'Call failed';
      case CallStateEnum.ENDED:
        return 'Call ended';
      default:
        return widget.service.isIncoming ? 'Incoming call' : 'Connecting…';
    }
  }

  /// mm:ss (or h:mm:ss) since the call connected; null before then.
  String? _durationLabel() {
    final start = _connectedAt;
    if (start == null) return null;
    final d = DateTime.now().difference(start);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    _attachStream();
    final service = widget.service;
    final incoming = service.isIncoming;
    final duration = _durationLabel();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF20463D), Color(0xFF0B1A17)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Offstage 1×1 view so remote audio is routed to the device.
              SizedBox(
                width: 1,
                height: 1,
                child: _rendererReady
                    ? RTCVideoView(_remote)
                    : const SizedBox.shrink(),
              ),
              const Spacer(flex: 2),
              CircleAvatar(
                radius: 58,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                child: Text(
                  _title().characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 50, color: Colors.white),
                ),
              ),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _title(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                duration ?? _status(),
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
              const Spacer(flex: 3),
              if (_showDtmf) ...[
                DialPad(compact: true, onKey: service.sendDtmf),
                TextButton(
                  onPressed: () => setState(() => _showDtmf = false),
                  child: const Text(
                    'Hide keypad',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _controls(context, service, incoming),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, SipService service, bool incoming) {
    if (incoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CircleBtn(
            icon: Icons.call_end_rounded,
            label: 'Decline',
            bg: Colors.red,
            onTap: service.hangup,
          ),
          _CircleBtn(
            icon: Icons.call_rounded,
            label: 'Answer',
            bg: Colors.green,
            onTap: service.answer,
          ),
        ],
      );
    }
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CircleBtn(
              icon: service.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: service.muted ? 'Unmute' : 'Mute',
              active: service.muted,
              onTap: service.toggleMute,
            ),
            _CircleBtn(
              icon: service.held
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded,
              label: service.held ? 'Resume' : 'Hold',
              active: service.held,
              onTap: service.toggleHold,
            ),
            _CircleBtn(
              icon: Icons.dialpad_rounded,
              label: 'Keypad',
              active: _showDtmf,
              onTap: () => setState(() => _showDtmf = !_showDtmf),
            ),
          ],
        ),
        const SizedBox(height: 28),
        _CircleBtn(
          icon: Icons.call_end_rounded,
          label: 'End',
          bg: Colors.red,
          size: 74,
          onTap: service.hangup,
        ),
      ],
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.bg,
    this.active = false,
    this.size = 62,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? bg;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final background =
        bg ?? (active ? Colors.white : Colors.white.withValues(alpha: 0.16));
    final fg = bg != null
        ? Colors.white
        : (active ? const Color(0xFF0B1A17) : Colors.white);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Material(
            color: background,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Icon(icon, color: fg, size: size * 0.42),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}
