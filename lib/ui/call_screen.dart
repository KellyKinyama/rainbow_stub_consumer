import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../rainbow/webrtc_adapter.dart';
import '../state/capsules/call_manager_capsule.dart';

/// Full-screen in-call surface — shown while a call is [active].
/// Renders remote video full-bleed with a small local preview in
/// the corner; falls back to a text avatar bubble when no video
/// track is present (audio-only calls).
class CallScreen extends RearchConsumer {
  const CallScreen({super.key, required this.sid});
  final String sid;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final manager = use(callManagerCapsule);
    return ListenableBuilder(
      listenable: manager,
      builder: (ctx, _) {
        final call = manager.calls[sid];
        if (call == null) {
          // Post-hangup: pop back to whatever's underneath.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.canPop(context)) Navigator.pop(context);
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(child: _RemoteVideo(call: call)),
                if (call.hasVideo)
                  Positioned(
                    right: 16,
                    top: 16,
                    width: 120,
                    height: 160,
                    child: _LocalVideoPreview(call: call),
                  ),
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _CallHeader(call: call),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: _CallControls(call: call, manager: manager),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CallHeader extends StatelessWidget {
  const _CallHeader({required this.call});
  final ActiveCall call;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          call.displayLabel,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          _stateLabel(call.state),
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  static String _stateLabel(CallState s) => switch (s) {
    CallState.idle => 'preparing…',
    CallState.dialing => 'dialing…',
    CallState.ringing => 'ringing…',
    CallState.connecting => 'connecting…',
    CallState.connected => 'connected',
    CallState.disconnected => 'reconnecting…',
    CallState.failed => 'call failed',
    CallState.ended => 'call ended',
  };
}

class _RemoteVideo extends StatefulWidget {
  const _RemoteVideo({required this.call});
  final ActiveCall call;

  @override
  State<_RemoteVideo> createState() => _RemoteVideoState();
}

class _RemoteVideoState extends State<_RemoteVideo> {
  final _renderer = RTCVideoRenderer();
  MediaStream? _boundStream;

  @override
  void initState() {
    super.initState();
    _renderer.initialize().then((_) => _bind());
  }

  @override
  void didUpdateWidget(_RemoteVideo old) {
    super.didUpdateWidget(old);
    _bind();
  }

  void _bind() {
    final stream = widget.call.session.remoteMediaStream;
    if (identical(stream, _boundStream)) return;
    _renderer.srcObject = stream;
    _boundStream = stream;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _renderer.srcObject = null;
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_boundStream == null || !widget.call.hasVideo) {
      return _AudioAvatar(call: widget.call);
    }
    return RTCVideoView(
      _renderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}

class _LocalVideoPreview extends StatefulWidget {
  const _LocalVideoPreview({required this.call});
  final ActiveCall call;

  @override
  State<_LocalVideoPreview> createState() => _LocalVideoPreviewState();
}

class _LocalVideoPreviewState extends State<_LocalVideoPreview> {
  final _renderer = RTCVideoRenderer();
  MediaStream? _boundStream;

  @override
  void initState() {
    super.initState();
    _renderer.initialize().then((_) => _bind());
  }

  @override
  void didUpdateWidget(_LocalVideoPreview old) {
    super.didUpdateWidget(old);
    _bind();
  }

  void _bind() {
    final stream = widget.call.session.localMediaStream;
    if (identical(stream, _boundStream)) return;
    _renderer.srcObject = stream;
    _boundStream = stream;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _renderer.srcObject = null;
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_boundStream == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: RTCVideoView(
        _renderer,
        mirror: true,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );
  }
}

class _AudioAvatar extends StatelessWidget {
  const _AudioAvatar({required this.call});
  final ActiveCall call;

  @override
  Widget build(BuildContext context) {
    final initial = call.displayLabel.isNotEmpty
        ? call.displayLabel.substring(0, 1).toUpperCase()
        : '?';
    return Center(
      child: CircleAvatar(
        radius: 72,
        backgroundColor: Colors.white24,
        child: Text(
          initial,
          style: const TextStyle(color: Colors.white, fontSize: 56),
        ),
      ),
    );
  }
}

class _CallControls extends StatefulWidget {
  const _CallControls({required this.call, required this.manager});
  final ActiveCall call;
  final CallManager manager;

  @override
  State<_CallControls> createState() => _CallControlsState();
}

class _CallControlsState extends State<_CallControls> {
  bool _muted = false;
  bool _cameraOn = true;

  @override
  void initState() {
    super.initState();
    _cameraOn = widget.call.hasVideo;
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingRinging =
        widget.call.direction == CallDirection.incoming &&
        widget.call.state == CallState.ringing;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CircleButton(
          icon: _muted ? Icons.mic_off : Icons.mic,
          color: Colors.white24,
          onTap: () async {
            setState(() => _muted = !_muted);
            await widget.call.session.setMicrophoneMuted(_muted);
          },
        ),
        if (widget.call.hasVideo) ...[
          const SizedBox(width: 12),
          _CircleButton(
            icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
            color: Colors.white24,
            onTap: () async {
              setState(() => _cameraOn = !_cameraOn);
              await widget.call.session.setCameraEnabled(_cameraOn);
            },
          ),
          const SizedBox(width: 12),
          _CircleButton(
            icon: Icons.cameraswitch,
            color: Colors.white24,
            onTap: () => widget.call.session.switchCamera(),
          ),
        ],
        const SizedBox(width: 12),
        if (isIncomingRinging)
          _CircleButton(
            icon: Icons.call,
            color: Colors.green,
            onTap: () => widget.manager.answer(widget.call.sid),
          )
        else
          _CircleButton(
            icon: Icons.call_end,
            color: Theme.of(context).colorScheme.error,
            onTap: () => widget.manager.hangUp(widget.call.sid),
          ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}
