import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';

import '../state/capsules/auth_controller_capsule.dart';
import '../state/capsules/rest_capsule.dart';

/// Single-step self-registration: create an (unverified) account with
/// email + password (+ optional name), then auto-sign-in. Email
/// verification is nudged afterwards via an in-app banner — the account
/// works immediately in the meantime.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
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

        Future<void> submit() async {
          final email = _email.text.trim();
          if (email.isEmpty || _password.text.isEmpty) {
            setState(() => _error = 'Email and password are required');
            return;
          }
          setState(() {
            _error = null;
            _busy = true;
          });
          try {
            final res = await rest.register(
              email: email,
              password: _password.text,
              firstName: _first.text.trim(),
              lastName: _last.text.trim(),
            );
            await auth.signIn(email, _password.text);
            if (!mounted) return;
            Navigator.of(context).pop();
            final code = res.devToken;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  code == null
                      ? 'Account created — check your email to verify.'
                      : 'Account created — verify your email (dev code: $code).',
                ),
                duration: const Duration(seconds: 6),
              ),
            );
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
                    Text(
                      'Create your account',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      onSubmitted: (_) => submit(),
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
                      onPressed: _busy ? null : submit,
                      child: Text(_busy ? 'Creating…' : 'Create account'),
                    ),
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
