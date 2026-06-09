import 'package:freezed_annotation/freezed_annotation.dart';

part 'inbox_item.freezed.dart';

enum InboxKind { commentReply, postReply, mention, message }

@freezed
class InboxItem with _$InboxItem {
  const InboxItem._();

  const factory InboxItem({
    required String fullname, // t1_ or t4_
    required InboxKind kind,
    required String author,
    required String subject,
    required String body,
    required DateTime created,
    @Default(false) bool isNew,
    String? context, // permalink for comment replies/mentions
    String? linkTitle,
    String? subreddit,
    String? dest,
    @Default(<InboxItem>[]) List<InboxItem> replies,
  }) = _InboxItem;

  bool get isMessage => kind == InboxKind.message;

  /// For comment replies/mentions: extracts (subreddit, postId) from `context`
  /// so the UI can open the post. Returns null if not derivable.
  ({String subreddit, String postId})? get postRef {
    final ctx = context;
    if (ctx == null) return null;
    final segs = ctx.split('?').first.split('/').where((s) => s.isNotEmpty).toList();
    final ci = segs.indexOf('comments');
    if (ci >= 1 && ci + 1 < segs.length) {
      return (subreddit: segs[ci - 1], postId: segs[ci + 1]);
    }
    return null;
  }

  factory InboxItem.fromChild(Map<String, dynamic> child) {
    final type = child['kind'] as String?;
    final d = child['data'] as Map<String, dynamic>? ?? {};
    final created = DateTime.fromMillisecondsSinceEpoch(
      ((d['created_utc'] as num?)?.toInt() ?? 0) * 1000,
      isUtc: true,
    );

    if (type == 't4') {
      final repliesRaw = d['replies'];
      final replies = <InboxItem>[];
      if (repliesRaw is Map) {
        final children = (repliesRaw['data']?['children'] as List?) ?? const [];
        for (final c in children) {
          replies.add(InboxItem.fromChild(c as Map<String, dynamic>));
        }
      }
      return InboxItem(
        fullname: d['name'] as String? ?? 't4_${d['id']}',
        kind: InboxKind.message,
        author: d['author'] as String? ?? '[unknown]',
        subject: (d['subject'] as String? ?? '').trim(),
        body: d['body'] as String? ?? '',
        created: created,
        isNew: d['new'] == true,
        dest: d['dest'] as String?,
        subreddit: d['subreddit'] as String?,
        replies: replies,
      );
    }

    // t1 comment in inbox
    final t = d['type'] as String?;
    final kind = switch (t) {
      'post_reply' => InboxKind.postReply,
      'username_mention' => InboxKind.mention,
      _ => InboxKind.commentReply,
    };
    return InboxItem(
      fullname: d['name'] as String? ?? 't1_${d['id']}',
      kind: kind,
      author: d['author'] as String? ?? '[deleted]',
      subject: (d['subject'] as String? ?? '').trim(),
      body: d['body'] as String? ?? '',
      created: created,
      isNew: d['new'] == true,
      context: d['context'] as String?,
      linkTitle: (d['link_title'] as String?)?.trim(),
      subreddit: d['subreddit'] as String?,
    );
  }
}
