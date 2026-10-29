import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/translate.dart';

void main() {
  test('batches keep order and respect both limits', () {
    final texts = ['aaaa', 'bb', 'cccccc', 'd', 'ee'];
    expect(Translate.batches(texts, 6, 10), [
      ['aaaa', 'bb'],
      ['cccccc'],
      ['d', 'ee'],
    ]);
    expect(Translate.batches(texts, 100, 2), [
      ['aaaa', 'bb'],
      ['cccccc', 'd'],
      ['ee'],
    ]);
    // A text longer than the limit goes alone.
    expect(Translate.batches(['aaaa', 'bb'], 3, 10), [
      ['aaaa'],
      ['bb'],
    ]);
  });
}
