import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/theme/app_theme.dart';
import 'package:luli_for_reddit/features/auth/auth_controller.dart';
import 'package:luli_for_reddit/features/post/comment_tree.dart';
import 'package:luli_for_reddit/features/post/comments_controller.dart';
import 'package:luli_for_reddit/features/post/post_detail_screen.dart';
import 'package:luli_for_reddit/features/settings/settings_controller.dart';
import 'package:luli_for_reddit/models/comment.dart';
import 'package:luli_for_reddit/models/post.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoAuth extends AuthController {
  @override
  Future<AuthSession?> build() async => null;
}

final _post = Post.fromData({
  'id': 'p1',
  'name': 't3_p1',
  'title': 'A thread',
  'subreddit': 'test',
  'subreddit_name_prefixed': 'r/test',
  'author': 'op',
  'score': 10,
  'num_comments': 4,
  'created_utc': 1700000000,
  'permalink': '/r/test/comments/p1/x/',
  'is_self': true,
  'selftext': 'Body text',
});

Comment _c(String id, String parent, int depth, String body,
        {List<Comment> replies = const []}) =>
    Comment.fromChild({
      'kind': 't1',
      'data': {
        'id': id,
        'name': 't1_$id',
        'author': id == 'a' ? 'op' : 'user_$id',
        'author_flair_text': 'Flair $id',
        'body': body,
        'score': 5,
        'parent_id': parent,
        'created_utc': 1700000000,
      },
    }, depth)
        .copyWith(replies: replies);

/// A thread with a reply chain, a folded top-level comment, a collapsed one
/// and a "more" row.
class _FakeComments extends CommentsController {
  @override
  Future<PostThread> build(String arg) async => PostThread(
        post: _post,
        comments: [
          _c('a', 't3_p1', 0, 'Top **comment**', replies: [
            _c('b', 't1_a', 1, 'A reply', replies: [
              _c('c', 't1_b', 2, 'שלום, תגובה בעברית'),
            ]),
          ]),
          _c('d', 't3_p1', 0, 'Folded parent',
              replies: [_c('e', 't1_d', 1, 'Hidden reply')]),
          _c('f', 't3_p1', 0, 'Collapsed one'),
          Comment.fromChild({
            'kind': 'more',
            'data': {
              'id': 'm',
              'name': 't1_m',
              'parent_id': 't3_p1',
              'count': 7,
              'children': ['x'],
            },
          }, 0),
        ],
        collapsed: {CommentTree.folded('d'), 'f'},
      );
}

void main() {
  for (final display in PostDisplay.values) {
    testWidgets('post screen renders as ${display.label}', (t) async {
      SharedPreferences.setMockInitialValues({'postDisplay': display.index});
      final prefs = await SharedPreferences.getInstance();
      // Tall enough to build every row.
      t.view.physicalSize = const Size(1200, 6000);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_NoAuth.new),
          commentsControllerProvider.overrideWith(_FakeComments.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(null),
          home: const PostDetailScreen(subreddit: 'test', postId: 'p1'),
        ),
      ));
      await t.pump();
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('A thread'), findsOneWidget);
      expect(find.text('A reply'), findsOneWidget);
      expect(find.text('Flair b'), findsOneWidget);
      expect(find.text('Show 1 reply'), findsOneWidget);
      expect(find.text('Hidden reply'), findsNothing);
      expect(find.text('7 more replies'), findsOneWidget);
      // Calm threads: labelled Collapse / Expand pills.
      final calm = display.isCalm;
      expect(find.text('Collapse'), calm ? findsWidgets : findsNothing);
      expect(find.text('Expand'), calm ? findsOneWidget : findsNothing);
    });
  }
}
