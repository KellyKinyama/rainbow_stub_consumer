import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';
import 'package:sip_ua/sip_ua.dart';

import '../rainbow/sip_service.dart';
import '../state/capsules/sip_capsule.dart';
import 'dial_pad.dart';
import 'sip_call_screen.dart';
import 'sip_settings_page.dart';

/// Softphone dialer: keypad + number field + call button, backed by a
/// SIP-over-WebSocket account ([SipService]). While a call is active it
/// hands off to [SipCallScreen].
class DialerPage extends RearchConsumer {
  const DialerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final service = use(sipServiceCapsule);
    final settingsAsync = use(sipSettingsCapsule);
    final (number, setNumber) = use.state<String>('');

    // Auto-connect once when saved settings are available.
    use.effect(() {
      if (settingsAsync case AsyncData<SipCreds>(:final data)) {
        if (data.isComplete &&
            service.registerState == RegistrationStateEnum.NONE) {
          service.connect(data);
        }
      }
      return null;
    }, [settingsAsync]);

    final configured = switch (settingsAsync) {
      AsyncData<SipCreds>(:final data) => data.isComplete,
      _ => false,
    };

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        if (service.hasActiveCall) {
          return SipCallScreen(service: service);
        }
        return _DialerBody(
          service: service,
          configured: configured,
          number: number,
          onNumberChanged: setNumber,
        );
      },
    );
  }
}

class _DialerBody extends StatelessWidget {
  const _DialerBody({
    required this.service,
    required this.configured,
    required this.number,
    required this.onNumberChanged,
  });

  final SipService service;
  final bool configured;
  final String number;
  final ValueChanged<String> onNumberChanged;

  void _openSettings(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SipSettingsPage()));

  Future<void> _call(BuildContext context) async {
    if (number.isEmpty) return;
    if (!service.isRegistered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not registered — check SIP settings')),
      );
      return;
    }
    final ok = await service.dial(number);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not place the call')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (regLabel, regColor) = switch (service.registerState) {
      RegistrationStateEnum.REGISTERED => ('Registered', Colors.green),
      RegistrationStateEnum.REGISTRATION_FAILED => (
        'Register failed',
        Colors.red,
      ),
      _ => ('Offline', Colors.grey),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Phone'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.circle, size: 10, color: regColor),
                const SizedBox(width: 4),
                Text(regLabel, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'SIP settings',
            icon: const Icon(Icons.settings),
            onPressed: () => _openSettings(context),
          ),
        ],
      ),
      body: !configured
          ? _NotConfigured(onOpen: () => _openSettings(context))
          : Column(
              children: [
                const Spacer(),
                SizedBox(
                  height: 64,
                  child: Center(
                    child: Text(
                      number.isEmpty ? 'Enter a number' : number,
                      style: TextStyle(
                        fontSize: 34,
                        letterSpacing: 1.5,
                        color: number.isEmpty
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                DialPad(onKey: (k) => onNumberChanged('$number$k')),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 72),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: Material(
                        color: Colors.green,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _call(context),
                          child: const Icon(
                            Icons.call,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 72,
                      child: number.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              iconSize: 28,
                              icon: const Icon(Icons.backspace_outlined),
                              onPressed: () => onNumberChanged(
                                number.substring(0, number.length - 1),
                              ),
                              onLongPress: () => onNumberChanged(''),
                            ),
                    ),
                  ],
                ),
                const Spacer(),
              ],
            ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dialpad, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No SIP account configured'),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Set up SIP account'),
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}
