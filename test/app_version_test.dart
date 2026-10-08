import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/reddit_constants.dart';

void main() {
  // The update checker compares GitHub's latest release with appVersion; if
  // it lags pubspec, an up-to-date install keeps being offered its own version.
  test('appVersion matches the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version =
        RegExp(r'^version:\s*([\d.]+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(RedditConstants.appVersion, version);
  });
}
