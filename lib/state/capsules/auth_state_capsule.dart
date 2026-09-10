import 'package:rearch/rearch.dart';

import '../models/auth_state.dart';

/// Shared writable [AuthState] slot. Exposed via [ValueWrapper] so both
/// the auth controller (writes) and other capsules (reads) can access it
/// without stale-closure hazards.
///
/// Consumers should call `use(authStateCapsule).value` for the current
/// value, or `use.stream(...)` on higher-level facades.
ValueWrapper<AuthState> authStateCapsule(CapsuleHandle use) =>
    use.data<AuthState>(const AuthState.signedOut());

/// Convenience getter for the current [AuthState] as a plain value.
AuthState authCapsule(CapsuleHandle use) => use(authStateCapsule).value;
