import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';

import '../state/capsules/rest_capsule.dart';

/// Two-step reset flow:
/// 1. Enter email → server emails a reset token (stub returns it in
///    the response body under `devToken` for dev demos).
/// 2. Enter the token + a new password → password is updated,
///    return to the login screen.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();
  final _token = TextEditingController();
  final _password = TextEditingController();
  int _step = 0;
  String? _devToken;
  String? _error;
  String? _notice;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RearchBuilder(
      builder: (context, use) {
        final rest = use(restCapsule);

        Future<void> submitEmail() async {
          setState(() {
            _error = null;
            _busy = true;
          });
          try {
            final token = await rest.resetPasswordSendEmail(_email.text.trim());
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

        Future<void> submitReset() async {
          setState(() {
            _error = null;
            _notice = null;
            _busy = true;
          });
          try {
            await rest.resetPassword(
              token: _token.text.trim(),
              password: _password.text,
            );
            if (!mounted) return;
            setState(() => _notice = 'Password updated — sign in below.');
            await Future<void>.delayed(const Duration(seconds: 1));
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
          appBar: AppBar(title: const Text('Reset password')),
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
                        child: Text(_busy ? 'Sending…' : 'Send reset email'),
                      ),
                    ] else ...[
                      Text(
                        'Confirm and set a new password',
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
                          labelText: 'Reset token',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'New password',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy ? null : submitReset,
                        child: Text(_busy ? 'Updating…' : 'Update password'),
                      ),
                    ],
                    if (_notice != null) ...[
                      const SizedBox(height: 12),
                      Text(_notice!, textAlign: TextAlign.center),
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
