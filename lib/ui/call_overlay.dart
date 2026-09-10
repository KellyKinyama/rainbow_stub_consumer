import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';

import '../rainbow/webrtc_adapter.dart';
import '../state/capsules/call_manager_capsule.dart';

/// M-3 call surface — a compact floating panel that appears whenever
/// [CallManager] has an [ActiveCall]. Renders "Incoming call from …"
/// with Accept / Decline buttons for incoming, or "Calling …" with a
/// hangup button for outgoing / in-progress.
class CallOverlay extends RearchConsumer {
  const CallOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final manager = use(callManagerCapsule);
    return ListenableBuilder(
      listenable: manager,
      builder: (ctx, _) {
        final call = manager.activeCall;
        if (call == null) return const SizedBox.shrink();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _CallCard(call: call, manager: manager),
          ),
        );
      },
    );
  }
}

class _CallCard extends StatelessWidget {
  const _CallCard({required this.call, required this.manager});
  final ActiveCall call;
  final CallManager manager;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncoming = call.direction == CallDirection.incoming;
    return Material(
      elevation: 4,
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.phone_in_talk),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isIncoming
                        ? 'Incoming call from ${call.peerId}'
                        : 'Calling ${call.peerId}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    _stateLabel(call.state),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (isIncoming && call.state == CallState.ringing)
              IconButton(
                icon: const Icon(Icons.call),
                color: Colors.green,
                onPressed: () => manager.answer(call.sid),
              ),
            IconButton(
              icon: const Icon(Icons.call_end),
              color: scheme.error,
              onPressed: () => manager.hangUp(call.sid),
            ),
          ],
        ),
      ),
    );
  }

  static String _stateLabel(CallState s) => switch (s) {
    CallState.idle => 'preparing…',
    CallState.dialing => 'dialing…',
    CallState.ringing => 'ringing…',
    CallState.connecting => 'connecting…',
    CallState.connected => 'connected',
    CallState.disconnected => 'reconnecting…',
    CallState.failed => 'failed',
    CallState.ended => 'ended',
  };
}
