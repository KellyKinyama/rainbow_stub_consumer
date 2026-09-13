import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';
import 'package:sip_ua/sip_ua.dart';

import '../rainbow/sip_service.dart';
import '../state/capsules/sip_capsule.dart';

/// SIP account + WebSocket transport settings for the dialer. The user
/// types the credentials here (including the password); they are stored
/// locally via [SipSettingsStore].
class SipSettingsPage extends RearchConsumer {
  const SipSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final settingsAsync = use(sipSettingsCapsule);
    final store = use(sipSettingsStoreCapsule);
    final refresher = use(sipSettingsRefresherCapsule);
    final service = use(sipServiceCapsule);

    return Scaffold(
      appBar: AppBar(title: const Text('SIP account')),
      body: switch (settingsAsync) {
        AsyncData<SipCreds>(:final data) => _SipSettingsForm(
          initial: data,
          service: service,
          onSave: (creds) async {
            await store.save(creds);
            refresher.bump();
            service.connect(creds);
          },
          onDisconnect: service.disconnect,
        ),
        AsyncError<SipCreds>(:final error) => Center(
          child: Text('Failed to load settings: $error'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _SipSettingsForm extends StatefulWidget {
  const _SipSettingsForm({
    required this.initial,
    required this.service,
    required this.onSave,
    required this.onDisconnect,
  });

  final SipCreds initial;
  final SipService service;
  final Future<void> Function(SipCreds) onSave;
  final Future<void> Function() onDisconnect;

  @override
  State<_SipSettingsForm> createState() => _SipSettingsFormState();
}

class _SipSettingsFormState extends State<_SipSettingsForm> {
  late final TextEditingController _ws = TextEditingController(
    text: widget.initial.wsUrl,
  );
  late final TextEditingController _aor = TextEditingController(
    text: widget.initial.aor,
  );
  late final TextEditingController _user = TextEditingController(
    text: widget.initial.authUser,
  );
  late final TextEditingController _pass = TextEditingController(
    text: widget.initial.password,
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.initial.displayName,
  );
  bool _obscure = true;

  @override
  void dispose() {
    _ws.dispose();
    _aor.dispose();
    _user.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  SipCreds _current() => SipCreds(
    wsUrl: _ws.text.trim(),
    aor: _aor.text.trim(),
    authUser: _user.text.trim(),
    password: _pass.text,
    displayName: _name.text.trim(),
  );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AnimatedBuilder(
          animation: widget.service,
          builder: (_, _) => _StatusChip(service: widget.service),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _ws,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'WebSocket URL',
            hintText: 'wss://sip.example.com:8089/ws',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _aor,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'SIP URI (AOR)',
            hintText: 'sip:1001@example.com',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _user,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Auth username',
            hintText: '1001',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pass,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Display name (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: const Icon(Icons.link),
          label: const Text('Save & connect'),
          onPressed: () async {
            final creds = _current();
            if (creds.wsUrl.isEmpty || creds.aor.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('WebSocket URL and SIP URI are required'),
                ),
              );
              return;
            }
            await widget.onSave(creds);
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Connecting…')));
            }
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.link_off),
          label: const Text('Disconnect'),
          onPressed: () => widget.onDisconnect(),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.service});
  final SipService service;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (service.registerState) {
      RegistrationStateEnum.REGISTERED => ('Registered', Colors.green),
      RegistrationStateEnum.REGISTRATION_FAILED => (
        service.lastError ?? 'Registration failed',
        Colors.red,
      ),
      _ => ('Not registered', Colors.grey),
    };
    return Row(
      children: [
        Icon(Icons.circle, size: 12, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
