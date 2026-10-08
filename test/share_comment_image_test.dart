import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/post/share_comment_image.dart';
import 'package:luli_for_reddit/models/comment.dart';
import 'package:luli_for_reddit/models/post.dart';

Comment _c(String id, String author, String body, String parent) =>
    Comment.fromChild({
      'kind': 't1',
      'data': {
        'id': id,
        'name': 't1_$id',
        'author': author,
        'body': body,
        'score': 42,
        'parent_id': parent,
        'created_utc': 1700000000,
      },
    }, 0);

void main() {
  testWidgets('renders the chain, hides names, captures a PNG', (t) async {
    final post = Post.fromData(
        {'id': 'p', 'title': 'A big post', 'subreddit': 'test', 'url': ''});
    final chain = [
      _c('a', 'alice', 'Top comment', 't3_p'),
      _c('b', 'bob', 'A reply', 't1_a'),
      _c('c', 'alice', 'Back to you', 't1_b'),
    ];
    await t.pumpWidget(MaterialApp(home: Builder(
        builder: (ctx) => TextButton(
            onPressed: () =>
                showShareCommentImage(ctx, post: post, chain: chain),
            child: const Text('go')))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();

    expect(find.text('A big post'), findsOneWidget);
    expect(find.textContaining('u/alice'), findsNWidgets(2));
    await t.tap(find.text('Hide usernames'));
    await t.pumpAndSettle();
    expect(find.textContaining('u/'), findsNothing);
    // Same author, same placeholder.
    expect(find.textContaining('Commenter 1'), findsNWidgets(2));
    expect(find.textContaining('Commenter 2'), findsOneWidget);

    final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first);
    await t.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 1);
      expect(img.width, greaterThan(100));
    });
  });
}
