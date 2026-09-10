import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../rainbow/sfu_group_call.dart';
import '../rainbow/webrtc_adapter.dart';
import '../state/capsules/group_call_capsule.dart';

/// Full-screen surface for an active group call.
///
/// Layout:
///   - background: adaptive grid of [RTCVideoView] tiles, one per
///     remote stream from [SfuGroupCallSession.remoteStreams];
///   - small mirrored local preview docked top-right;
///   - bottom control row: mic, camera, camera-flip, leave.
///
/// Auto-pops when the manager no longer tracks a joined call for
/// [roomBareJid] (e.g. peer terminates the room, or leave completes).
class GroupCallScreen extends RearchConsumer {
  const GroupCallScreen({super.key, required this.roomBareJid});
  final String roomBareJid;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final manager = use(groupCallManagerCapsule);
    return ListenableBuilder(
      listenable: manager,
      builder: (ctx, _) {
        final call = manager.joinedCalls[roomBareJid];
        if (call == null) {
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
                Positioned.fill(child: _RemoteGrid(session: call.session)),
                Positioned(
                  right: 12,
                  top: 12,
                  width: 120,
                  height: 160,
                  child: _LocalPreview(session: call.session),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: _CallControls(
                      session: call.session,
                      onLeave: () => manager.leaveGroupCall(
                        roomBareJid,
                        announceEnd: false,
                      ),
                    ),
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

class _RemoteGrid extends StatefulWidget {
  const _RemoteGrid({required this.session});
  final SfuGroupCallSession session;

  @override
  State<_RemoteGrid> createState() => _RemoteGridState();
}

class _RemoteGridState extends State<_RemoteGrid> {
  List<MediaStream> _streams = const [];
  StreamSubscription<List<MediaStream>>? _sub;

  @override
  void initState() {
    super.initState();
    _streams = widget.session.currentRemoteStreams;
    _sub = widget.session.remoteStreams.listen((s) {
      if (mounted) setState(() => _streams = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_streams.isEmpty) return const _EmptyState();
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final columns = _columnsFor(_streams.length, constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 4 / 3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: _streams.length,
          itemBuilder: (_, i) => _RemoteTile(stream: _streams[i]),
        );
      },
    );
  }

  static int _columnsFor(int tiles, double width) {
    if (tiles <= 1) return 1;
    if (tiles <= 4) return 2;
    if (width < 600) return 2;
    return 3;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups, size: 80, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            'Waiting for others to join…',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _RemoteTile extends StatefulWidget {
  const _RemoteTile({required this.stream});
  final MediaStream stream;

  @override
  State<_RemoteTile> createState() => _RemoteTileState();
}

class _RemoteTileState extends State<_RemoteTile> {
  final _renderer = RTCVideoRenderer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _renderer.initialize().then((_) {
      _renderer.srcObject = widget.stream;
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void didUpdateWidget(_RemoteTile old) {
    super.didUpdateWidget(old);
    if (!identical(old.stream, widget.stream)) {
      _renderer.srcObject = widget.stream;
    }
  }

  @override
  void dispose() {
    _renderer.srcObject = null;
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: Colors.white10,
        child: _ready
            ? RTCVideoView(
                _renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _LocalPreview extends StatefulWidget {
  const _LocalPreview({required this.session});
  final SfuGroupCallSession session;

  @override
  State<_LocalPreview> createState() => _LocalPreviewState();
}

class _LocalPreviewState extends State<_LocalPreview> {
  final _renderer = RTCVideoRenderer();
  MediaStream? _bound;

  @override
  void initState() {
    super.initState();
    _renderer.initialize().then((_) => _bind());
  }

  @override
  void didUpdateWidget(_LocalPreview old) {
    super.didUpdateWidget(old);
    _bind();
  }

  void _bind() {
    final stream = widget.session.session?.localMediaStream;
    if (identical(stream, _bound)) return;
    _renderer.srcObject = stream;
    _bound = stream;
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
    if (_bound == null) return const SizedBox.shrink();
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

class _CallControls extends StatefulWidget {
  const _CallControls({required this.session, required this.onLeave});
  final SfuGroupCallSession session;
  final VoidCallback onLeave;

  @override
  State<_CallControls> createState() => _CallControlsState();
}

class _CallControlsState extends State<_CallControls> {
  bool _muted = false;
  bool _cameraOn = true;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CircleButton(
          icon: _muted ? Icons.mic_off : Icons.mic,
          color: Colors.white24,
          onTap: () async {
            setState(() => _muted = !_muted);
            await widget.session.setMicrophoneMuted(_muted);
          },
        ),
        const SizedBox(width: 12),
        _CircleButton(
          icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
          color: Colors.white24,
          onTap: () async {
            setState(() => _cameraOn = !_cameraOn);
            await widget.session.setCameraEnabled(_cameraOn);
          },
        ),
        const SizedBox(width: 12),
        _CircleButton(
          icon: Icons.cameraswitch,
          color: Colors.white24,
          onTap: () => widget.session.switchCamera(),
        ),
        const SizedBox(width: 12),
        _CircleButton(
          icon: Icons.call_end,
          color: Theme.of(context).colorScheme.error,
          onTap: widget.onLeave,
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
