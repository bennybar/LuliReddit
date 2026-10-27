import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/theme/app_theme.dart';
import 'package:luli_for_reddit/features/auth/auth_controller.dart';
import 'package:luli_for_reddit/features/feed/post_card.dart';
import 'package:luli_for_reddit/features/settings/settings_controller.dart';
import 'package:luli_for_reddit/models/post.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

class _NoAuth extends AuthController {
  @override
  Future<AuthSession?> build() async => null;
}

// A text post with everything a card can show but images (no network in
// tests): a For You reason, flair, a crosspost line and a poll with results.
final _post = Post.fromData({
  'id': 'p1',
  'name': 't3_p1',
  'title': 'Which layout do you like?',
  'subreddit': 'polls',
  'subreddit_name_prefixed': 'r/polls',
  'author': 'someone',
  'score': 1234,
  'num_comments': 56,
  'created_utc': 1700000000,
  'permalink': '/r/polls/comments/p1/x/',
  'is_self': true,
  'selftext': 'Pick one.',
  'link_flair_text': ':q: Question',
  'poll_data': {
    'options': [
      {'id': '1', 'text': 'Calm', 'vote_count': 30},
      {'id': '2', 'text': 'Cards', 'vote_count': 10},
    ],
    'user_selection': '1',
  },
}).copyWith(feedReason: 'Popular in r/polls · r/polls');

void main() {
  // No pending visibility timers when a test ends.
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
  galleryTests();
  for (final display in PostDisplay.values) {
    testWidgets('PostCard renders as ${display.label}', (t) async {
      SharedPreferences.setMockInitialValues({'postDisplay': display.index});
      final prefs = await SharedPreferences.getInstance();
      await t.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_NoAuth.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(null),
          home: Scaffold(
            body: ListView(children: [
              PostCard(post: _post, dismissible: true, frontpage: true),
            ]),
          ),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Which layout do you like?'), findsOneWidget);
      // Mini cards show no poll.
      final poll = display == PostDisplay.mini ? findsNothing : findsOneWidget;
      expect(find.text('You voted · 40 votes'), poll);
      expect(find.text('75%'), poll);
      if (display.isCalm) {
        // The reason sits in the header, without the repeated subreddit.
        expect(find.text('Popular in r/polls'), findsOneWidget);
        expect(find.text('Question'), findsOneWidget); // cleaned flair
      } else {
        expect(find.text('Popular in r/polls · r/polls'), findsOneWidget);
      }
    });
  }
}

// Gallery posts: the M3 carousel lays out in every layout (images themselves
// don't load in tests).
final _gallery = Post.fromData({
  'id': 'g1',
  'title': 'Three photos',
  'subreddit': 'pics',
  'url': 'https://www.reddit.com/gallery/g1',
  'gallery_data': {
    'items': [
      {'media_id': 'a'},
      {'media_id': 'b'},
      {'media_id': 'c'},
    ],
  },
  'media_metadata': {
    for (final id in ['a', 'b', 'c'])
      id: {
        'status': 'valid',
        's': {'u': 'https://i.redd.it/$id.jpg', 'x': 800, 'y': 600},
      },
  },
});

void galleryTests() {
  for (final display in PostDisplay.values) {
    if (display == PostDisplay.mini) continue;
    testWidgets('gallery carousel in ${display.label}', (t) async {
      SharedPreferences.setMockInitialValues({'postDisplay': display.index});
      final prefs = await SharedPreferences.getInstance();
      await t.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_NoAuth.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(null),
          home: Scaffold(
            body: ListView(children: [PostCard(post: _gallery)]),
          ),
        ),
      ));
      await t.pump();
      expect(_gallery.type, PostType.gallery);
      expect(find.byType(CarouselView), findsOneWidget);
      expect(find.bySemanticsLabel('Image 1 of 3'), findsOneWidget);
      expect(find.text('3 images · tap one to view'), findsOneWidget);
    });
  }
}
