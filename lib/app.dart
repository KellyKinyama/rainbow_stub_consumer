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
import 'ui/theme_tokens.dart';

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
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
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


ThemeData _buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: PhoneTokens.accent,
    brightness: Brightness.light,
    surface: PhoneTokens.lightPanelBg,
    surfaceContainer: PhoneTokens.lightBodyBg,
    surfaceContainerHighest: PhoneTokens.lightRowSelected,
    onSurface: PhoneTokens.lightTextPrimary,
    onSurfaceVariant: PhoneTokens.lightTextSecondary,
    outline: PhoneTokens.lightDivider,
    primary: PhoneTokens.accent,
    error: PhoneTokens.danger,
  );
  return _buildTheme(scheme, PhoneTokens.lightBodyBg);
}

ThemeData _buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: PhoneTokens.accent,
    brightness: Brightness.dark,
    surface: PhoneTokens.darkPanelBg,
    surfaceContainer: PhoneTokens.darkBodyBg,
    surfaceContainerHighest: PhoneTokens.darkRowSelected,
    onSurface: PhoneTokens.darkTextPrimary,
    onSurfaceVariant: PhoneTokens.darkTextSecondary,
    outline: PhoneTokens.darkDivider,
    primary: PhoneTokens.accent,
    error: PhoneTokens.danger,
  );
  return _buildTheme(scheme, PhoneTokens.darkBodyBg);
}

ThemeData _buildTheme(ColorScheme scheme, Color scaffoldBg) {
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: scaffoldBg,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: scheme.outline)),
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontFamily: PhoneTokens.fontFamily,
        fontWeight: FontWeight.w500,
        fontSize: PhoneTokens.sectionHeadingFontSize,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      minVerticalPadding: 4,
      horizontalTitleGap: 12,
    ),
    dividerTheme: DividerThemeData(color: scheme.outline, thickness: 1, space: 1),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PhoneTokens.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: PhoneTokens.accent),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: scheme.onSurface),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: PhoneTokens.accent,
      foregroundColor: Colors.white,
      shape: const CircleBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.surfaceContainerHighest,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      labelTextStyle: WidgetStateProperty.all(
        TextStyle(fontFamily: PhoneTokens.fontFamily, fontSize: 12),
      ),
    ),
    textTheme: base.textTheme.apply(
      fontFamily: PhoneTokens.fontFamily,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
  );
}
