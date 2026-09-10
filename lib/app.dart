import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';

import 'state/capsules/auth_state_capsule.dart';
import 'state/models/auth_state.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';

class RainbowConsumerApp extends StatelessWidget {
  const RainbowConsumerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rainbow Stub Consumer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0086CF)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends RearchConsumer {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final auth = use(authCapsule);
    return auth is SignedIn ? const HomePage() : const LoginPage();
  }
}
