import 'dart:convert';

import '../core/media_links.dart' show giphyUrl;

// Website sign-in: when Reddit's edge refuses a thread's .json (403, as it did
// search and /by_id), the thread loads like in Reddit's app: the post by id
// and its comment forest from PostComments, mapped to the comments response
// the app already parses (and saves for offline reading).
const gqlPostComments =
    '8a25ae56c1d4813102f4eded0c427b99f46f6a63f77630e78767f27ef5186f1f';

/// A "more" row from GraphQL holds its cursor as its only child id, behind
/// this prefix: getMoreComments continues it through PostComments, since
/// /api/morechildren only takes comment ids.
const gqlMore = 'gql:';

// The comment fragment's switches; off: what the app doesn't show.
const _commentFlags = {
  'includeAwards': false,
  'includeCommentsHtmlField': false,
  'includeIsGildable': false,
  'includeModerationInfo': false,
  'subredditUserPostEditingAllowed': false,
  'includeExtendedVideoAsset': true,
  'includePlaybackMp4s': true,
  'includeMuxedMp4s': true,
  'includeVideoPlaybackInComments': false,
  'includeCommentViewStats': false,
  'includePremiumAvatarTreatment': false,
  'includeCommentFollowedForNotificationsStatus': false,
  'includeCommentEntityHighlights': false,
  'includeRedditHandleInfo': false,
  'includeVerificationStatus': false,
};

const _commentSorts = {
  'confidence': 'CONFIDENCE',
  'top': 'TOP',
  'new': 'NEW',
  'controversial': 'CONTROVERSIAL',
  'old': 'OLD',
  'qa': 'QA',
};

/// PostComments' variables: a post's comments ([after]: a "more" row's
/// cursor), or [focusCommentId]'s thread with 3 parents, like the website's
/// `?comment=…&context=3`. Reddit sends at most 25 comments per request.
Map<String, dynamic> gqlPostCommentsVariables(String postFullname, String sort,
        String? focusCommentId, String? after) =>
    {
      ..._commentFlags,
      'id': postFullname,
      'maxDepth': 10,
      'count': 200,
      'includeAdEligibility': false,
      'isUserMod': false,
      'skipPostInfoFragment': true,
      'includeConsistencyToken': false,
      'callerContext': {'referrer': 'FEED'},
      if (_commentSorts[sort] != null) 'sortType': _commentSorts[sort],
      if (after != null) 'after': after,
      if (focusCommentId != null) ...{
        'focusedCommentContext': {
          'commentId': 't1_$focusCommentId',
          'isFocusedThreadOnly': true,
          'minDeepCommentParents': 3,
        },
        'numParents': 3,
      },
    };

/// PostComments' comment forest: its flat list of comments and "more" entries.
List<dynamic> gqlTrees(Map<String, dynamic> data) =>
    ((data['postInfoById'] as Map?)?['commentForest'] as Map?)?['trees']
        as List? ??
    const [];

// A richtext media asset's URL, largest size first.
String? _mediaUrl(Map? m) {
  for (final size in const ['xxxlarge', 'xxlarge', 'xlarge', 'large', 'medium']) {
    final url = (m?[size] as Map?)?['url'];
    if (url is String) return url;
  }
  return m?['url'] as String?;
}

/// PostComments' forest (a flat, depth-first list of comments and "more"
/// entries) as listing things (kind t1 / more), each naming its parent: the
/// shape /api/morechildren returns. Depths are relative (a loaded "more"
/// starts deeper, a focused thread's parents are negative), so the shallowest
/// entries hang off the forest's own parent, else [linkFullname].
List<Map<String, dynamic>> gqlCommentThings(
    List<dynamic> trees, String linkFullname,
    {String? moreParent}) {
  int? depthOf(Object? t) => ((t as Map?)?['depth'] as num?)?.toInt();
  final depths = trees.map(depthOf).nonNulls;
  final base = depths.isEmpty ? 0 : depths.reduce((a, b) => a < b ? a : b);
  // ancestors[d]: the latest comment at relative depth d.
  final ancestors = <String>[];
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < trees.length; i++) {
    final tree = trees[i];
    if (tree is! Map) continue;
    final depth = depthOf(tree) ?? base;
    final level = depth - base;
    final String parent;
    if (level == 0) {
      // A loaded "more" ([moreParent]): its shallowest entries are that
      // row's replies, whatever form Reddit's parentId takes
      // (CommentTree.replaceMore attaches them by it).
      parent = moreParent ?? tree['parentId'] as String? ?? linkFullname;
    } else if (level - 1 < ancestors.length) {
      parent = ancestors[level - 1];
    } else {
      continue;
    }
    final more = tree['more'] as Map?;
    if (more != null) {
      final cursor = more['cursor'] as String?;
      if (cursor == null) continue;
      out.add({
        'kind': 'more',
        'data': {
          'id': 'more_$parent',
          'name': 'more_$parent',
          'parent_id': parent,
          'count': (more['count'] as num?)?.toInt() ?? 0,
          // The row's parent travels with its cursor, for when it loads.
          'children': ['$gqlMore$parent $cursor'],
        },
      });
      continue;
    }
    final n = tree['node'] as Map?;
    if (n == null) continue;
    // A deleted comment comes without its id, but the replies under it name
    // it as their parent (Reddit only keeps deleted ones with replies).
    var name = n['id'] as String?;
    for (var j = i + 1; name == null && j < trees.length; j++) {
      final d = depthOf(trees[j]) ?? depth;
      if (d <= depth) break;
      if (d == depth + 1) name = (trees[j] as Map)['parentId'] as String?;
    }
    name ??= 't1_deleted$i';
    ancestors
      ..length = level
      ..add(name);
    final content = n['content'] as Map?;
    final deleted =
        n['__typename'] != 'Comment' || n['isRemoved'] == true || content == null;
    final category = n['removedByCategory'];
    final gone =
        category == null || category == 'DELETED' ? '[deleted]' : '[removed]';
    final flair = n['authorFlair'] as Map?;
    final id = name.replaceFirst('t1_', '');
    // Uploaded images and GIFs the markdown names by id (`![img](id)`).
    final media = {
      for (final m in (content?['richtextMedia'] as List?) ?? const [])
        if ((m as Map?)?['id'] is String) m!['id'] as String: _mediaUrl(m)
    };
    out.add({
      'kind': 't1',
      'data': <String, dynamic>{
        'id': id,
        'name': name,
        'parent_id': parent,
        'author': deleted
            ? '[deleted]'
            : ((n['authorInfo'] as Map?)?['name'] ?? '[deleted]'),
        'body': deleted ? gone : gqlMarkdown(content, id),
        'score': (n['score'] as num?)?.toInt() ?? 0,
        'created_utc':
            (DateTime.tryParse('${n['createdAt']}')?.millisecondsSinceEpoch ??
                    0) /
                1000,
        'distinguished': switch (n['distinguishedAs']) {
          'MODERATOR' => 'moderator',
          'ADMIN' => 'admin',
          _ => null,
        },
        'stickied': n['isStickied'] == true,
        'score_hidden': n['isScoreHidden'] == true,
        'saved': n['isSaved'] == true,
        'is_submitter': n['isOP'] == true,
        'likes': switch (n['voteState']) { 'UP' => true, 'DOWN' => false, _ => null },
        'permalink': n['permalink'],
        // The flair's richtext is a JSON string here, an array on the website.
        if (flair?['richtext'] is String)
          'author_flair_richtext': _tryDecode(flair!['richtext'] as String),
        'author_flair_text': flair?['text'],
        if (media.isNotEmpty)
          'media_metadata': {
            for (final e in media.entries)
              e.key: e.value == null
                  ? {'status': 'unprocessed'}
                  : {
                      'status': 'valid',
                      's': {'u': e.value},
                    },
          },
      },
    });
  }
  return out;
}

Object? _tryDecode(String json) {
  try {
    return jsonDecode(json);
  } catch (_) {
    return null;
  }
}

/// PostsByIds' post and PostComments' forest as a thread's comments response
/// (`[post listing, comment listing]`), which parseThread reads and the
/// offline copy keeps.
List<dynamic> gqlThreadData(Map<String, dynamic> post, List<dynamic> trees) {
  final things = gqlCommentThings(trees, '${post['name']}');
  final byParent = <String?, List<Map<String, dynamic>>>{};
  for (final t in things) {
    byParent.putIfAbsent(t['data']['parent_id'] as String?, () => []).add(t);
  }
  final names = {for (final t in things) t['data']['name']};
  Map<String, dynamic> nest(Map<String, dynamic> t) {
    final replies = byParent[t['data']['name']];
    if (replies == null) return t;
    return {
      ...t,
      'data': {
        ...t['data'] as Map<String, dynamic>,
        'replies': {
          'data': {'children': replies.map(nest).toList()},
        },
      },
    };
  }

  return [
    {
      'data': {
        'children': [
          {'kind': 't3', 'data': post},
        ],
      },
    },
    {
      'data': {
        'children': [
          for (final t in things)
            if (!names.contains(t['data']['parent_id'])) nest(t)
        ],
      },
    },
  ];
}

// Markdown's inline syntax, escaped in plain text so it reads literally.
final _mdSpecial = RegExp(r'[\\`*_~^\[\]>]');

/// A comment's body as markdown. The source markdown when Reddit sends it
/// (what editing, copying and translating need); otherwise converted from the
/// richtext, Reddit's own parse of the markdown as JSON:
///  - blocks: par, h{l}, blockquote, list{o} > li, code > raw lines, hr,
///    table{h, c}, img / gif / video{id}
///  - inline: text{t, f}, link{u, t, f}, r/ and u/{t, l}, spoilertext{c},
///    br, raw{t}, img / gif / video{id}
///  - f: [bits, start, length] ranges of t, counted in code points; bits
///    1 bold, 2 italic, 8 strike, 32 superscript, 64 code.
/// Media become bare links, which the comment renderer shows as media.
String gqlMarkdown(Map? content, String thingId) {
  final markdown = content?['markdown'];
  if (markdown is String && markdown.isNotEmpty) return markdown;
  final richtext = content?['richtext'];
  final decoded = richtext is String ? _tryDecode(richtext) : null;
  final doc = decoded is Map ? decoded['document'] : null;
  if (doc is! List) return '';
  final media = {
    for (final m in (content?['richtextMedia'] as List?) ?? const [])
      if (m is Map) m['id']: m
  };
  String escape(String t) => t.replaceAllMapped(_mdSpecial, (m) => '\\${m[0]}');
  String mediaLink(Map n) {
    final id = n['id'];
    if (id is! String) return '';
    // The player link Reddit's own HTML used for videos in a body.
    if (n['e'] == 'video') return 'https://reddit.com/link/$thingId/video/$id/player';
    return giphyUrl(id) ?? _mediaUrl(media[id]) ?? '';
  }

  String formatted(Map n, String Function(String) render) {
    final cps = '${n['t'] ?? ''}'.runes.toList();
    String slice(int from, int to) {
      final a = from.clamp(0, cps.length);
      return String.fromCharCodes(cps.sublist(a, to.clamp(a, cps.length)));
    }

    final ranges = [
      for (final r in (n['f'] as List?) ?? const [])
        if (r is List && r.isNotEmpty && r[0] is num)
          (
            bits: (r[0] as num).toInt(),
            start: r.length > 1 ? (r[1] as num).toInt() : 0,
            length: r.length > 2 ? (r[2] as num).toInt() : 0,
          )
    ]..sort((a, b) => a.start.compareTo(b.start));
    final out = StringBuffer();
    var pos = 0;
    for (final (:bits, :start, :length) in ranges) {
      if (start > pos) out.write(render(slice(pos, start)));
      final text = slice(start > pos ? start : pos, start + length);
      if (start + length > pos) pos = start + length;
      final core = text.trim();
      if (core.isEmpty) {
        out.write(render(text));
        continue;
      }
      // Markers must touch the text: `** bold**` isn't bold.
      var md = bits & 64 != 0 ? '`$core`' : render(core);
      if (bits & 32 != 0) md = '^($md)';
      if (bits & 8 != 0) md = '~~$md~~';
      if (bits & 2 != 0) md = '*$md*';
      if (bits & 1 != 0) md = '**$md**';
      final at = text.indexOf(core);
      out
        ..write(text.substring(0, at))
        ..write(md)
        ..write(text.substring(at + core.length));
    }
    if (pos < cps.length) out.write(render(slice(pos, cps.length)));
    return out.toString();
  }

  String inline(Object? nodes) => [
        for (final n in (nodes as List?) ?? const [])
          if (n is Map)
            switch (n['e']) {
              'text' => formatted(n, escape),
              'link' => formatted(n, (t) {
                  final url = '${n['u'] ?? ''}'
                      .replaceAll(' ', '%20')
                      .replaceAll('(', '%28')
                      .replaceAll(')', '%29');
                  return '[${escape(t)}]($url)';
                }),
              'r/' || 'u/' =>
                '${n['l'] == true || n['l'] == 1 ? '/' : ''}${n['e']}${n['t'] ?? ''}',
              'spoilertext' => '>!${inline(n['c'])}!<',
              'br' => '  \n',
              'img' || 'gif' || 'video' => mediaLink(n),
              _ => escape('${n['t'] ?? ''}'),
            }
      ].join();

  String blocks(Object? nodes) => [
        for (final n in (nodes as List?) ?? const [])
          if (n is Map)
            switch (n['e']) {
              'par' => inline(n['c']),
              'h' => '${'#' * ((n['l'] as num?)?.toInt() ?? 1).clamp(1, 6)} '
                  '${inline(n['c'])}',
              'blockquote' => blocks(n['c'])
                  .split('\n')
                  .map((l) => l.isEmpty ? '>' : '> $l')
                  .join('\n'),
              'list' => [
                  for (final (i, li) in ((n['c'] as List?) ?? const []).indexed)
                    for (final marker in [n['o'] == true ? '${i + 1}. ' : '- '])
                      marker +
                          blocks((li as Map?)?['c'])
                              .split('\n')
                              .join('\n${' ' * marker.length}'),
                ].join('\n'),
              'code' => '```\n${[
                  for (final l in (n['c'] as List?) ?? const [])
                    '${(l as Map?)?['t'] ?? ''}'
                ].join('\n')}\n```',
              'hr' => '---',
              'table' => [
                  [for (final h in (n['h'] as List?) ?? const []) inline((h as Map)['c'])],
                  [
                    for (final h in (n['h'] as List?) ?? const [])
                      switch ((h as Map)['a']) {
                        'L' => ':--',
                        'C' => ':-:',
                        'R' => '--:',
                        _ => '---',
                      }
                  ],
                  for (final row in (n['c'] as List?) ?? const [])
                    [for (final cell in (row as List?) ?? const []) inline((cell as Map?)?['c'])],
                ].map((r) => '| ${r.join(' | ')} |').join('\n'),
              'img' || 'gif' || 'video' => mediaLink(n),
              // Anything newer: its inline content, or its text.
              _ => n['c'] is List ? inline(n['c']) : escape('${n['t'] ?? ''}'),
            }
      ].join('\n\n');

  return blocks(doc);
}
