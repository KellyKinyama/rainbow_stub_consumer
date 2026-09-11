import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';

import '../state/capsules/auth_controller_capsule.dart';
import '../state/capsules/rest_capsule.dart';

/// Multi-step self-registration flow:
/// 1. Enter email → server emails a confirmation token (stub returns
///    it in the response body under `devToken` so demos can skip a
///    real mailbox).
/// 2. Enter the token + a password (+ optional first/last name) →
///    server creates the account, we auto-sign-in and return.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _email = TextEditingController();
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  int _step = 0;
  String? _devToken;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _password.dispose();
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RearchBuilder(
      builder: (context, use) {
        final rest = use(restCapsule);
        final auth = use(authControllerCapsule);

        Future<void> submitEmail() async {
          setState(() {
            _error = null;
            _busy = true;
          });
          try {
            final token = await rest.selfRegisterSendEmail(_email.text.trim());
            if (!mounted) return;
            setState(() {
              _devToken = token;
              _token.text = token;
              _step = 1;
            });
          } on Object catch (e) {
            if (!mounted) return;
            setState(() => _error = e.toString());
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        }

        Future<void> submitProfile() async {
          setState(() {
            _error = null;
            _busy = true;
          });
          try {
            await rest.selfRegister(
              token: _token.text.trim(),
              password: _password.text,
              firstName: _first.text.trim(),
              lastName: _last.text.trim(),
            );
            await auth.signIn(_email.text.trim(), _password.text);
            if (!mounted) return;
            Navigator.of(context).pop();
          } on Object catch (e) {
            if (!mounted) return;
            setState(() => _error = e.toString());
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Create account')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_step == 0) ...[
                      Text(
                        'Enter your email',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                        onSubmitted: (_) => submitEmail(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy ? null : submitEmail,
                        child: Text(_busy ? 'Sending…' : 'Send confirmation'),
                      ),
                    ] else ...[
                      Text(
                        'Confirm and set password',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      if (_devToken != null)
                        Text(
                          'Dev token: $_devToken',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _token,
                        decoration: const InputDecoration(
                          labelText: 'Confirmation token',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _first,
                        decoration: const InputDecoration(
                          labelText: 'First name (optional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _last,
                        decoration: const InputDecoration(
                          labelText: 'Last name (optional)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy ? null : submitProfile,
                        child: Text(_busy ? 'Creating…' : 'Create account'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
