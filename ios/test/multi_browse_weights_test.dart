import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/media/gallery_carousel.dart';

void main() {
  test('large image is 280 wide plus its padding, as in Kotlin', () {
    // An iPhone 17 Pro Max feed card is about 426 wide.
    final w = multiBrowseWeights(426, 5);
    expect(w.first, 288);
    expect(w.last, 64); // 56 small + padding
    expect(w.reduce((a, b) => a + b), 426);
  });

  test('two images: large and the rest', () {
    expect(multiBrowseWeights(426, 2), [288, 138]);
  });

  test('narrow widths keep the large image at 80%', () {
    final w = multiBrowseWeights(300, 4);
    expect(w.first, 240);
    expect(w.length, 2); // no room for a medium and a small
  });
}
