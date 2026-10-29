import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/data/gql_comments.dart';
import 'package:luli_for_reddit/models/comment.dart';
import 'package:luli_for_reddit/models/post.dart';

Map<String, dynamic> comment(String id, String author, String markdown,
        [Map<String, dynamic> extra = const {}]) =>
    {
      '__typename': 'Comment',
      'id': id,
      'authorInfo': {'name': author},
      'content': {'markdown': markdown},
      'score': 5,
      'createdAt': '2026-10-04T00:26:11.575000+0000',
      'permalink': '/r/pics/comments/abc/a_post/${id.substring(3)}/',
      ...extra,
    };

// PostComments' forest: a flat, depth-first list.
final trees = [
  {
    'depth': 0,
    'parentId': 't3_abc',
    'node': comment('t1_c1', 'alice', 'Hello', {
      'isOP': true,
      'isStickied': true,
      'distinguishedAs': 'MODERATOR',
      'voteState': 'UP',
      'isSaved': true,
      'authorFlair': {'text': 'Mod', 'richtext': '[{"e":"text","t":"Mod"}]'},
    }),
  },
  {'depth': 1, 'parentId': 't1_c1', 'node': comment('t1_c2', 'bob', 'Reply')},
  {'depth': 2, 'parentId': 't1_c2', 'more': {'count': 4, 'cursor': 'cur-deep'}},
  {
    'depth': 0,
    'parentId': 't3_abc',
    'node': {'__typename': 'DeletedComment', 'createdAt': '2026-10-04T00:26:11+0000'},
  },
  {
    'depth': 1,
    'parentId': 't1_gone',
    'node': comment('t1_c3', 'carol', 'Under a deleted one', {'voteState': 'DOWN'}),
  },
  {'depth': 0, 'parentId': 't3_abc', 'more': {'count': 30, 'cursor': 'cur-top'}},
];

Map<String, dynamic> richtext(List document, [List media = const []]) => {
      'richtext': jsonEncode({'document': document}),
      'richtextMedia': media,
    };

Map<String, dynamic> par(List c) => {'e': 'par', 'c': c};
Map<String, dynamic> text(String t, [List? f]) =>
    {'e': 'text', 't': t, if (f != null) 'f': f};

void main() {
  test("a comment forest becomes the thread's comment tree", () {
    final body = gqlThreadData({
      'id': 'abc',
      'name': 't3_abc',
      'title': 'A post',
      'author': 'alice',
      'subreddit': 'pics',
      'permalink': '/r/pics/comments/abc/a_post/',
    }, trees);
    final postData = ((body[0] as Map)['data']['children'] as List).first['data'];
    expect(Post.fromData(postData as Map<String, dynamic>).id, 'abc');
    final top = [
      for (final c in (body[1] as Map)['data']['children'] as List)
        Comment.fromChild(c as Map<String, dynamic>, 0)
    ];
    expect(top.map((c) => c.id), ['c1', 'gone', 'more_t3_abc']);

    final c1 = top[0];
    expect(c1.author, 'alice');
    expect(c1.body, 'Hello');
    expect(c1.score, 5);
    expect(c1.created, DateTime.utc(2026, 10, 4, 0, 26, 11));
    expect(c1.distinguished, 'moderator');
    expect(c1.stickied && c1.saved, isTrue);
    expect(c1.likes, isTrue);
    expect(c1.authorFlair?.parts.single.text, 'Mod');
    expect(c1.parentId, 't3_abc');

    final c2 = c1.replies.single;
    expect(c2.depth, 1);
    expect(c2.parentId, 't1_c1');
    final deep = c2.replies.single;
    expect(deep.isMore, isTrue);
    expect(deep.depth, 2);
    expect(deep.moreCount, 4);
    expect(deep.parentId, 't1_c2');
    expect(deep.moreChildren, ['${gqlMore}t1_c2 cur-deep']);

    // The deleted comment gets its id back from its reply.
    final gone = top[1];
    expect(gone.author, '[deleted]');
    expect(gone.body, '[deleted]');
    expect(gone.fullname, 't1_gone');
    expect(gone.replies.single.likes, isFalse);

    final more = top[2];
    expect(more.isMore, isTrue);
    expect(more.moreCount, 30);
    expect(more.parentId, 't3_abc');
    expect(more.moreChildren, ['${gqlMore}t3_abc cur-top']);
  });

  test('a loaded more comes flat, rooted where the more row was', () {
    // The page after cursor cur-deep: depths continue from where it sat.
    final page = [
      {'depth': 2, 'node': comment('t1_d1', 'dan', 'One')},
      {'depth': 3, 'parentId': 't1_d1', 'node': comment('t1_d2', 'erin', 'Two')},
      {'depth': 2, 'parentId': 't1_c2', 'more': {'count': 2, 'cursor': 'cur-next'}},
    ];
    // Rooted at the row's parent even where Reddit leaves parentId out.
    final flat = [
      for (final t in gqlCommentThings(page, 't3_abc', moreParent: 't1_c2'))
        Comment.fromChild(t, 2)
    ];
    expect(flat.map((c) => c.parentId), ['t1_c2', 't1_d1', 't1_c2']);
    expect(flat.last.moreChildren, ['${gqlMore}t1_c2 cur-next']);
  });

  test("focused threads and more use PostComments' variables", () {
    final vars = gqlPostCommentsVariables('t3_abc', 'qa', 'c9', null);
    expect(vars['sortType'], 'QA');
    expect(vars['focusedCommentContext']['commentId'], 't1_c9');
    expect(vars.containsKey('after'), isFalse);
    expect(
        gqlPostCommentsVariables('t3_abc', 'confidence', null, 'cur')['after'],
        'cur');
  });

  test('the source markdown wins over richtext', () {
    expect(
        gqlMarkdown({'markdown': '**hi**', 'richtext': '{"document":[]}'}, 'c1'),
        '**hi**');
  });

  test('richtext becomes markdown', () {
    final md = gqlMarkdown(
      richtext([
        {'e': 'h', 'l': 2, 'c': [text('Title')]},
        par([
          text('bold italic struck 2*3', [
            [1, 0, 4],
            [2, 5, 6],
            [8, 12, 6],
          ]),
          {'e': 'link', 'u': 'https://example.com/a (b)', 't': 'a link'},
          text(' '),
          {'e': 'spoilertext', 'c': [text('secret')]},
          text(' in '),
          {'e': 'r/', 't': 'pics', 'l': false},
          {'e': 'br'},
          text('x', [
            [64, 0, 1]
          ]),
          text('e=mc2', [
            [32, 4, 1]
          ]),
        ]),
        {
          'e': 'blockquote',
          'c': [par([text('quoted')]), par([text('more')])],
        },
        {
          'e': 'list',
          'o': true,
          'c': [
            {'e': 'li', 'c': [par([text('one')])]},
            {
              'e': 'li',
              'c': [
                par([text('two')]),
                {
                  'e': 'list',
                  'o': false,
                  'c': [
                    {'e': 'li', 'c': [par([text('sub')])]},
                  ],
                },
              ],
            },
          ],
        },
        {
          'e': 'code',
          'c': [
            {'e': 'raw', 't': 'val x = 1'},
            {'e': 'raw', 't': '  *y*'},
          ],
        },
        {'e': 'hr'},
        par([
          {'e': 'gif', 'id': 'giphy|abc123|downsized'}
        ]),
        {'e': 'img', 'id': 'img1'},
        {
          'e': 'table',
          'h': [
            {'a': 'L', 'c': [text('A')]},
            {'c': [text('B')]},
          ],
          'c': [
            [
              {'c': [text('1')]},
              {'c': [text('2')]},
            ],
          ],
        },
      ], [
        {
          'id': 'img1',
          'url': 'https://i.redd.it/full.png',
          'large': {'url': 'https://preview.redd.it/large.png'},
        },
      ]),
      'c1',
    );
    expect(
      md,
      [
        '## Title',
        '**bold** *italic* ~~struck~~ 2\\*3[a link](https://example.com/a%20%28b%29) >!secret!< in r/pics  \n`x`e=mc^(2)',
        '> quoted\n>\n> more',
        '1. one\n2. two\n   \n   - sub',
        '```\nval x = 1\n  *y*\n```',
        '---',
        'https://media.giphy.com/media/abc123/giphy.webp',
        'https://preview.redd.it/large.png',
        '| A | B |\n| :-- | --- |\n| 1 | 2 |',
      ].join('\n\n'),
    );
  });

  test('formatting skips whitespace and counts code points', () {
    // "😀 wow ok": the emoji is one code point, so " wow ok" is 1 to 8.
    final md = gqlMarkdown(
        richtext([
          par([
            text('😀 wow ok', [
              [1, 1, 7]
            ]),
          ]),
        ]),
        'c1');
    expect(md, '😀 **wow ok**');
  });
}
