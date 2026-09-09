import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'state/rainbow_session.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';

class RainbowConsumerApp extends StatelessWidget {
  const RainbowConsumerApp({super.key, required this.config});
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RainbowSession(config),
      child: MaterialApp(
        title: 'Rainbow Stub Consumer',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0086CF)),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<RainbowSession>();
    return s.isAuthenticated ? const HomePage() : const LoginPage();
  }
}
