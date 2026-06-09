import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/secure_store.dart';
import 'auth_repository.dart';

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(secureStoreProvider)),
);

/// The signed-in session. `null` means no user → show the login screen.
class AuthSession {
  const AuthSession({required this.username});
  final String username;
}

class AuthController extends AsyncNotifier<AuthSession?> {
  SecureStore get _store => ref.read(secureStoreProvider);
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<AuthSession?> build() async {
    final token = await _store.accessToken;
    final username = await _store.username;
    if (token == null || username == null) return null;
    return AuthSession(username: username);
  }

  /// Runs the full interactive login. Caller catches [AuthException] to display
  /// the precise reason. On success the controller flips to the logged-in state.
  Future<void> login({
    required String clientId,
    required String redirectUri,
  }) async {
    final username = await _repo.login(clientId: clientId, redirectUri: redirectUri);
    state = AsyncData(AuthSession(username: username));
  }

  Future<void> logout() async {
    await _store.clearSession();
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);
