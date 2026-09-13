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

  @override
  void initState() {
    super.initState();
    _remote.initialize().then((_) {
      if (!mounted) return;
      setState(() => _rendererReady = true);
      _attachStream();
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

  @override
  Widget build(BuildContext context) {
    _attachStream();
    final service = widget.service;
    final incoming = service.isIncoming;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
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
            const Spacer(),
            CircleAvatar(
              radius: 48,
              backgroundColor: scheme.primaryContainer,
              child: Text(
                _title().characters.first.toUpperCase(),
                style: const TextStyle(fontSize: 40),
              ),
            ),
            const SizedBox(height: 16),
            Text(_title(), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(_status(), style: Theme.of(context).textTheme.bodyLarge),
            const Spacer(),
            if (_showDtmf) ...[
              DialPad(compact: true, onKey: service.sendDtmf),
              const SizedBox(height: 12),
            ],
            _controls(context, service, incoming),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, SipService service, bool incoming) {
    if (incoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundAction(
            icon: Icons.call_end,
            color: Colors.red,
            label: 'Decline',
            onTap: service.hangup,
          ),
          _RoundAction(
            icon: Icons.call,
            color: Colors.green,
            label: 'Answer',
            onTap: service.answer,
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundAction(
          icon: service.muted ? Icons.mic_off : Icons.mic,
          color: service.muted ? Colors.orange : Colors.blueGrey,
          label: service.muted ? 'Unmute' : 'Mute',
          onTap: service.toggleMute,
        ),
        _RoundAction(
          icon: Icons.dialpad,
          color: _showDtmf ? Colors.blue : Colors.blueGrey,
          label: 'Keypad',
          onTap: () => setState(() => _showDtmf = !_showDtmf),
        ),
        _RoundAction(
          icon: Icons.call_end,
          color: Colors.red,
          label: 'End',
          onTap: service.hangup,
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
