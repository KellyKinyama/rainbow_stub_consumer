import 'package:rearch/rearch.dart';

import '../../rainbow/sip_service.dart';

/// Bump [version] to force [sipSettingsCapsule] to reload after a save.
class SipSettingsRefresher {
  const SipSettingsRefresher(this.version, this.bump);
  final int version;
  final void Function() bump;
}

SipSettingsRefresher sipSettingsRefresherCapsule(CapsuleHandle use) {
  final (v, setV) = use.state<int>(0);
  return SipSettingsRefresher(v, () => setV(v + 1));
}

SipSettingsStore sipSettingsStoreCapsule(CapsuleHandle use) =>
    const SipSettingsStore();

/// The persisted SIP account settings.
AsyncValue<SipCreds> sipSettingsCapsule(CapsuleHandle use) {
  final store = use(sipSettingsStoreCapsule);
  final refresher = use(sipSettingsRefresherCapsule);
  final future = use.memo(() => store.load(), [refresher.version]);
  return use.future(future);
}

/// Long-lived SIP UA service (one per app). Disposed with the container.
SipService sipServiceCapsule(CapsuleHandle use) {
  final service = use.memo(() => SipService(), const []);
  use.effect(() => service.dispose, const []);
  return service;
}
