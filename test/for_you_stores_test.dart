import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/auth/auth_controller.dart';
import 'package:luli_for_reddit/features/foryou/for_you_stores.dart';
import 'package:luli_for_reddit/features/history/interest_store.dart';
import 'package:luli_for_reddit/features/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signed in as [user]; [switchTo] changes account.
class _FakeAuth extends AuthController {
  _FakeAuth(this.user);
  final String user;

  @override
  Future<AuthSession?> build() async => AuthSession(username: user);

  void switchTo(String u) => state = AsyncData(AuthSession(username: u));
}

Future<(ProviderContainer, SharedPreferences)> _container(
    [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(p),
    authControllerProvider.overrideWith(() => _FakeAuth('alice')),
  ]);
  await c.read(authControllerProvider.future);
  return (c, p);
}

void main() {
  test('a common word is counted in every title of a batch', () async {
    final (c, _) = await _container();
    final store = c.read(docFreqProvider.notifier);
    store.observe(List.filled(100, 'Commonword'));
    expect(c.read(docFreqProvider)['commonword'], closeTo(100, 0.001));
    expect(store.idf('commonword'), closeTo(0.2, 0.001));
  });

  test('loading then learning does not decay an old weight twice', () async {
    final old = DateTime.now()
        .subtract(const Duration(days: 10))
        .millisecondsSinceEpoch;
    final (c, _) = await _container(
        {'interest_weights_alice': '{"_ts":$old,"oldsub":10.0}'});
    final store = c.read(interestStoreProvider.notifier);
    c.read(interestStoreProvider);
    final justLoaded = store.weightFor('oldsub');
    store.bump('newsub', 1);
    expect(store.weightFor('oldsub'), closeTo(justLoaded, 0.001));
  });

  test('pending impressions do not move to another account', () async {
    final (c, p) = await _container();
    c.read(impressionStoreProvider.notifier).record('alice_post');
    (c.read(authControllerProvider.notifier) as _FakeAuth).switchTo('bob');
    c.read(impressionStoreProvider); // rebuilds for bob
    expect(c.read(impressionStoreProvider.notifier).count('alice_post'), 0);
    // …and they were saved to Alice's.
    expect(p.getString('fy_impressions_alice'), contains('alice_post'));
  });
}
