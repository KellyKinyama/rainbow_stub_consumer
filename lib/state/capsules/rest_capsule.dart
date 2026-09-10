import 'package:rearch/rearch.dart';

import '../../rainbow/rest_client.dart';
import 'config_capsule.dart';

/// Long-lived [RainbowRestClient] tied to the current [AppConfig].
///
/// Auto-disposed when the enclosing rearch container is disposed. Recreated
/// only if [configCapsule] emits a new [AppConfig] instance.
RainbowRestClient restCapsule(CapsuleHandle use) {
  final config = use(configCapsule);
  return use.disposable<RainbowRestClient>(
    () => RainbowRestClient(config),
    (client) => client.close(),
    [config],
  );
}
