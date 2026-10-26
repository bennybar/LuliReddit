import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/data/ai_service.dart';
import 'package:luli_for_reddit/features/post/comment_tree.dart';
import 'package:luli_for_reddit/models/comment.dart';
import 'package:luli_for_reddit/models/post.dart';

Comment c(String id, String author, String body, String parent,
        {int depth = 0, List<Comment> replies = const []}) =>
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
    }, depth)
        .copyWith(replies: replies);

Comment more(String id, String parent, int depth, List<String> children) =>
    Comment(
      id: id,
      fullname: 't1_$id',
      parentId: parent,
      author: '',
      body: '',
      score: 0,
      created: DateTime.fromMillisecondsSinceEpoch(0),
      depth: depth,
      isMore: true,
      moreCount: children.length,
      moreChildren: children,
    );

/// Port of the Android app's CommentTreeTest.
void main() {
  final chain = [
    c('a', 'alice', 'Top comment', 't3_p'),
    c('b', 'bob', 'A reply', 't1_a', depth: 1),
    c('c', 'alice', 'Back to you', 't1_b', depth: 2),
  ];

  test('share image names, hidden consistently', () {
    expect(CommentTree.shareNames(chain, false),
        ['u/alice', 'u/bob', 'u/alice']);
    // Same author, same placeholder.
    expect(CommentTree.shareNames(chain, true),
        ['Commenter 1', 'Commenter 2', 'Commenter 1']);
  });

  test('chain runs from the top-level ancestor to the comment', () {
    final flat = [c('x', 'x', 'other', 't3_p'), ...chain];
    expect(CommentTree.chainTo(flat, chain[2]).map((e) => e.id),
        ['a', 'b', 'c']);
    expect(CommentTree.chainTo(flat, chain[0]).map((e) => e.id), ['a']);
  });

  test('flatten skips collapsed, folded and more subtrees', () {
    final tree = [
      c('a', 'u', '', 't3_p', replies: [
        c('b', 'u', '', 't1_a',
            depth: 1, replies: [c('c', 'u', '', 't1_b', depth: 2)])
      ])
    ];
    expect(CommentTree.flatten(tree, {}).map((e) => e.id), ['a', 'b', 'c']);
    expect(CommentTree.flatten(tree, {'b'}).map((e) => e.id), ['a', 'b']);
    final folded = CommentTree.flatten(tree, {CommentTree.folded('a')});
    expect(folded.map((e) => e.id), ['a']);
    expect(CommentTree.replyCount(tree.first), 2);
  });

  test('insert, update and remove keep the tree consistent', () {
    final tree = [
      c('a', 'u', '', 't3_p', replies: [c('b', 'u', '', 't1_a', depth: 1)]),
      c('z', 'u', '', 't3_p'),
    ];
    final inserted =
        CommentTree.insertReply(tree, 't1_b', c('n', 'me', 'new', 't1_b'));
    expect(inserted[0].replies[0].replies[0].depth, 2);
    // Untouched subtrees keep their identity.
    final updated =
        CommentTree.update(tree, 't1_b', (x) => x.copyWith(score: 1));
    expect(updated[0].replies[0].score, 1);
    expect(identical(updated[1], tree[1]), isTrue);
    // A deleted comment with replies stays as "[deleted]".
    final removed = CommentTree.remove(tree, 't1_a');
    expect(removed[0].author, '[deleted]');
    expect(removed.skip(1).map((e) => e.id), ['z']);
    expect(CommentTree.remove(tree, 't1_z').map((e) => e.id), ['a']);
  });

  test('load more re-nests the flat result in place of the stub', () {
    final stub = more('m', 't1_a', 1, ['x', 'y']);
    final tree = [
      c('a', 'u', '', 't3_p',
          replies: [c('b', 'u', '', 't1_a', depth: 1), stub])
    ];
    final fetched = [c('x', 'u', '', 't1_a'), c('y', 'u', '', 't1_x')];
    final out = CommentTree.replaceMore(tree, stub, fetched);
    final replies = out[0].replies;
    expect(replies.map((e) => e.id), ['b', 'x']);
    expect(replies[1].depth, 1);
    expect(replies[1].replies.single.id, 'y');
    expect(replies[1].replies.single.depth, 2);
    expect(CommentTree.flatten(out, {}).any((e) => e.isMore), isFalse);
  });

  test('continue-thread stubs get unique ids from their parent', () {
    Comment stub(String parent) => Comment.fromChild({
          'kind': 'more',
          'data': {
            'id': '_',
            'name': 't1__',
            'parent_id': parent,
            'children': <String>[],
          },
        }, 3);
    expect(stub('t1_a').fullname, 'more_t1_a');
    expect(stub('t1_b').id, isNot(stub('t1_a').id));
  });

  test('thread text ranks comments by score within the budget', () {
    final post = Post.fromData({
      'id': 'p',
      'title': 'A big post',
      'subreddit': 'test',
      'author': 'op',
      'url': '',
      'is_self': true,
      'selftext': 'Body',
      'score': 10,
      'num_comments': 2,
    });
    final low = c('l', 'low', 'meh', 't3_p').copyWith(score: 1);
    final high =
        c('h', 'high', 'x', 't3_p').copyWith(score: 99, body: 'great\nline');
    final text = AiService.buildThreadText(
        post, [low, high, more('m', 't3_p', 0, ['q'])], 100000);
    expect(
        text.startsWith('POST in r/test by u/op — score 10, 2 comments\n'
            'TITLE: A big post\nBODY: Body\n'),
        isTrue);
    expect(text.indexOf('[99] u/high: great line'),
        lessThan(text.indexOf('[1] u/low: meh')));
    expect(text.endsWith('(Included 2 of 2 comments, highest-scored first.)'),
        isTrue);
    final tight = AiService.buildThreadText(post, [low, high], 120);
    expect(tight.endsWith('(Included 0 of 2 comments, highest-scored first.)'),
        isTrue);
  });
}
