import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import 'state/capsules/auth_controller_capsule.dart';
import 'state/capsules/auth_state_capsule.dart';
import 'state/capsules/call_manager_capsule.dart';
import 'state/models/auth_state.dart';
import 'ui/call_overlay.dart';
import 'ui/diagnostics_overlay.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';

/// Root navigator handle. Handed to [MaterialApp.navigatorKey] so
/// widgets that sit above the Navigator (the incoming-call overlay
/// inside `MaterialApp.builder`) can still push routes onto it.
final rootNavigatorKey = GlobalKey<NavigatorState>();

class RainbowConsumerApp extends StatelessWidget {
  const RainbowConsumerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rainbow Stub Consumer',
      navigatorKey: rootNavigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0086CF)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const _AuthGate(),
      // Stacks the incoming-call banner above every route so it stays
      // visible inside chat pages, bubble pages, etc.
      builder: (context, child) => Stack(
        children: [
          if (child != null) Positioned.fill(child: child),
          const Align(alignment: Alignment.topCenter, child: CallOverlay()),
        ],
      ),
    );
  }
}

class _AuthGate extends RearchConsumer {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    // Reading the controller triggers the boot effect that attempts
    // silent re-auth from SessionStore.
    use(authControllerCapsule);
    final auth = use(authCapsule);
    // Checking is a transient state during silent re-auth; treat it as
    // signed-out for the UI (LoginPage renders) so widget tests can
    // pumpAndSettle without waiting on a spinner.
    final home = auth is SignedIn
        ? const _CallLifecycleWatcher(child: HomePage())
        : const LoginPage();
    if (!kDebugMode) return home;
    return Stack(
      children: [
        Positioned.fill(child: home),
        const DiagnosticsOverlay(),
      ],
    );
  }
}

/// Bridges Flutter's [AppLifecycleState] to [CallManager] so the
/// ringer stops while the app is backgrounded.
class _CallLifecycleWatcher extends RearchConsumer {
  const _CallLifecycleWatcher({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final manager = use(callManagerCapsule);
    use.effect(() {
      final observer = _LifecycleObserver(manager.onAppLifecycleStateChanged);
      WidgetsBinding.instance.addObserver(observer);
      return () => WidgetsBinding.instance.removeObserver(observer);
    }, [manager]);
    return child;
  }
}

class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver(this._onChange);
  final void Function(AppLifecycleState) _onChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _onChange(state);
}
