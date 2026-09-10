// Widget smoke test proving Phase A: RearchBootstrapper composes over
// the existing provider-driven app tree without a crash and renders the
// initial LoginPage.
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/app.dart';
import 'package:rainbow_stub_consumer/config.dart';

void main() {
  testWidgets('RearchBootstrapper wraps RainbowConsumerApp without crash',
      (tester) async {
    await tester.pumpWidget(
      RearchBootstrapper(
        child: RainbowConsumerApp(config: AppConfig.dev),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // LoginPage renders with the pre-filled dev credentials + Sign-in button.
    expect(find.text('Rainbow Stub Consumer'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('alice@rainbow-stub.local'), findsOneWidget);
  });
}