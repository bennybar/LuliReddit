import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/about/whats_new.dart';

void main() {
  test('versions compare by number, not text', () {
    expect(newerVersion('2.0.30', '2.0.29'), isTrue);
    expect(newerVersion('2.0.10', '2.0.9'), isTrue);
    expect(newerVersion('2.1.0', '2.0.99'), isTrue);
    expect(newerVersion('2.0.29', '2.0.29'), isFalse);
    expect(newerVersion('2.0.8', '2.0.29'), isFalse);
  });

  // Kotlin also checks that the newest entry is this build's version; the
  // list is still the Kotlin app's, so only the order is checked here.
  test('newest release first', () {
    for (var i = 0; i + 1 < changelog.length; i++) {
      final a = changelog[i].version, b = changelog[i + 1].version;
      expect(newerVersion(a.split(' ').last, b.split(' ').last), isTrue,
          reason: '$a before $b');
    }
  });
}
