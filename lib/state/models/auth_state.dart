import '../../rainbow/models.dart';

/// Snapshot of who is signed in and their bearer token.
sealed class AuthState {
  const AuthState();

  const factory AuthState.signedOut() = SignedOut;
  const factory AuthState.signedIn({
    required RainbowUser me,
    required String token,
  }) = SignedIn;

  bool get isSignedIn => this is SignedIn;
  RainbowUser? get me => switch (this) {
    SignedIn(:final me) => me,
    _ => null,
  };
  String? get token => switch (this) {
    SignedIn(:final token) => token,
    _ => null,
  };
}

final class SignedOut extends AuthState {
  const SignedOut();
}

final class SignedIn extends AuthState {
  const SignedIn({required this.me, required this.token});

  @override
  final RainbowUser me;
  @override
  final String token;
}
