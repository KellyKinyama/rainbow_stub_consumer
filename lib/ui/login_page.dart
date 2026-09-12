import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../state/capsules/auth_controller_capsule.dart';
import '../state/capsules/config_capsule.dart';
import 'forgot_password_page.dart';
import 'register_page.dart';
import 'theme_tokens.dart';

class LoginPage extends RearchConsumer {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final auth = use(authControllerCapsule);
    final config = use(configCapsule);
    final email = use.textEditingController(
      initialText: 'alice@rainbow-stub.local',
    );
    final password = use.textEditingController(initialText: 'password');
    final (busy, setBusy) = use.state<bool>(false);
    final (error, setError) = use.state<String?>(null);

    Future<void> submit() async {
      setBusy(true);
      setError(null);
      try {
        await auth.signIn(email.text.trim(), password.text);
      } catch (e) {
        setError(e.toString());
      } finally {
        setBusy(false);
      }
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: phonePaletteOf(context).panelBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: phonePaletteOf(context).divider),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 20,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: PhoneTokens.accent,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.phone_in_talk,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Rainbow Stub Consumer',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      style: const TextStyle(color: PhoneTokens.danger),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy ? null : submit,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const RegisterPage(),
                          ),
                        ),
                        child: const Text('Create account'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ForgotPasswordPage(),
                          ),
                        ),
                        child: const Text('Forgot password?'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Points at ${config.baseUrl}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: phonePaletteOf(context).textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}
