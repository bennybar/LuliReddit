import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/network/reddit_client.dart';
import '../models/comment.dart';
import '../models/flair.dart';
import '../models/inbox_item.dart';
import '../models/listing.dart';
import '../models/multireddit.dart';
import '../models/post.dart';
import '../models/reddit_user.dart';
import '../models/subreddit.dart';

/// Sort options for post listings.
enum PostSort { best, hot, newest, top, rising }

extension PostSortApi on PostSort {
  String get path => switch (this) {
        PostSort.best => 'best',
        PostSort.hot => 'hot',
        PostSort.newest => 'new',
        PostSort.top => 'top',
        PostSort.rising => 'rising',
      };
  String get label => switch (this) {
        PostSort.best => 'Best',
        PostSort.hot => 'Hot',
        PostSort.newest => 'New',
        PostSort.top => 'Top',
        PostSort.rising => 'Rising',
      };
  bool get needsTime => this == PostSort.top;
}

enum TopTime { hour, day, week, month, year, all }

extension TopTimeApi on TopTime {
  String get param => name == 'all' ? 'all' : name;
  String get label => switch (this) {
        TopTime.hour => 'Now',
        TopTime.day => 'Today',
        TopTime.week => 'This week',
        TopTime.month => 'This month',
        TopTime.year => 'This year',
        TopTime.all => 'All time',
      };
}

class RedditRepository {
  RedditRepository(this._client);
  final RedditClient _client;

  Listing<Post> _parsePostListing(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>?;
    final children = (data?['children'] as List?) ?? const [];
    final posts = <Post>[];
    for (final c in children) {
      final kind = (c as Map)['kind'];
      if (kind == 't3') {
        posts.add(Post.fromData(c['data'] as Map<String, dynamic>));
      }
    }
    return Listing(items: posts, after: data?['after'] as String?);
  }

  /// "For You (Beta)" — a transparent, client-side personalized feed.
  ///
  /// Reddit's real Home ranking is server-side ML and is NOT exposed to the
  /// API, so this approximates it: candidate generation from /best (your
  /// subscriptions) + r/popular, then a local score blending engagement
  /// velocity, recency, your local affinity (subreddits you open), with a
  /// penalty for already-seen posts, plus a per-subreddit diversity cap.
  Future<Listing<Post>> getForYouFeed({
    Map<String, double> interest = const {},
    Set<String> seen = const {},
    Set<String> muted = const {},
  }) async {
    // Your communities are the backbone of the feed.
    List<Subreddit> mySubs = const [];
    try {
      mySubs = await getSubscribedSubreddits();
    } catch (_) {}
    final favourites = {
      for (final s in mySubs)
        if (s.userHasFavorited) s.name.toLowerCase()
    };
    final subscribed = {for (final s in mySubs) s.name.toLowerCase()};
    double interestOf(String sub) => interest[sub.toLowerCase()] ?? 0;

    // Subreddits you engage with most (learned on-device), even if not favourited.
    final topInterest = (interest.entries.where((e) => e.value >= 2).toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .map((e) => e.key)
        .toList();

    Future<Listing<Post>> safe(Future<Listing<Post>> f) =>
        f.catchError((_) => const Listing<Post>(items: []));

    // Candidate generation, multi-signal:
    //  • /best       — your subscription frontpage (the bulk)
    //  • favourites  — fresh hot from each (well represented)
    //  • interests   — hot from your most-engaged communities
    //  • rising      — what's heating up in your subscriptions (freshness)
    //  • r/popular   — a small discovery slice
    final fetches = <Future<Listing<Post>>>[
      safe(getPosts(sort: PostSort.best, limit: 100)),
      safe(getPosts(sort: PostSort.rising, limit: 25)),
      for (final f in favourites.take(8))
        safe(getPosts(subreddit: f, sort: PostSort.hot, limit: 10)),
      for (final s in topInterest)
        if (!favourites.contains(s))
          safe(getPosts(subreddit: s, sort: PostSort.hot, limit: 8)),
      safe(getPosts(subreddit: 'popular', sort: PostSort.hot, limit: 20)),
    ];
    final results = await Future.wait(fetches);

    final ids = <String>{};
    final unique = <Post>[];
    for (final listing in results) {
      for (final p in listing.items) {
        if (p.stickied) continue;
        if (muted.contains(p.subreddit.toLowerCase())) continue;
        if (ids.add(p.id)) unique.add(p);
      }
    }

    final now = DateTime.now().toUtc();
    bool isPrimary(Post p) {
      final sub = p.subreddit.toLowerCase();
      return favourites.contains(sub) ||
          subscribed.contains(sub) ||
          interestOf(sub) >= 2;
    }

    double scoreOf(Post p) {
      final sub = p.subreddit.toLowerCase();
      final ageH = now.difference(p.created).inMinutes / 60.0;
      final age = ageH < 1 ? 1.0 : ageH;
      final velocity = p.score / age; // engagement per hour
      final recency = 1 / (1 + age / 24); // soft decay over a day
      final quality = 0.5 + p.upvoteRatio; // 0.5–1.5
      // Community weight dominates ranking: favourites ≫ subscribed ≫ discovery,
      // boosted by your learned interest in that community.
      final base = favourites.contains(sub)
          ? 4.0
          : subscribed.contains(sub)
              ? 2.5
              : 0.4;
      final w = base + (interestOf(sub).clamp(0, 12)) * 0.35;
      final seenPenalty = seen.contains(p.id) ? 0.3 : 1.0;
      return (velocity * 0.5 + recency * 30 + 20) * w * quality * seenPenalty;
    }

    // Per-post "why you're seeing this" label.
    String reasonFor(Post p) {
      final sub = p.subreddit.toLowerCase();
      if (favourites.contains(sub)) return '★ Favourite · r/${p.subreddit}';
      if (interestOf(sub) >= 4) {
        return 'Because you engage with r/${p.subreddit}';
      }
      if (subscribed.contains(sub)) return 'From r/${p.subreddit}';
      final ageH = now.difference(p.created).inMinutes / 60.0;
      if (ageH < 6 && p.score > 1000) return '🔥 Trending on Reddit';
      return 'Discover · r/${p.subreddit}';
    }

    int byScore(Post a, Post b) => scoreOf(b).compareTo(scoreOf(a));

    List<Post> capPerSub(List<Post> posts, int cap) {
      final perSub = <String, int>{};
      final out = <Post>[];
      for (final p in posts) {
        final n = perSub[p.subreddit] ?? 0;
        if (n < cap) {
          out.add(p.copyWith(feedReason: reasonFor(p)));
          perSub[p.subreddit] = n + 1;
        }
      }
      return out;
    }

    final primary = capPerSub(unique.where(isPrimary).toList()..sort(byScore), 4);
    final discovery =
        capPerSub(unique.where((p) => !isPrimary(p)).toList()..sort(byScore), 2);

    // Mostly your communities, with a light discovery sprinkle (~1 in 6,
    // capped at 20% of the feed) for serendipity.
    final out = <Post>[];
    final discoveryCap = (primary.length * 0.2).ceil();
    var di = 0;
    for (var i = 0; i < primary.length; i++) {
      out.add(primary[i]);
      if ((i + 1) % 5 == 0 && di < discovery.length && di < discoveryCap) {
        out.add(discovery[di++]);
      }
    }
    if (out.isEmpty) out.addAll(discovery); // no subscriptions → discovery only
    return Listing(items: out, after: null);
  }

  /// Frontpage (subreddit == null) or a specific subreddit's posts.
  Future<Listing<Post>> getPosts({
    String? subreddit,
    PostSort sort = PostSort.best,
    TopTime time = TopTime.day,
    String? after,
    int limit = 25,
  }) async {
    final base = subreddit == null ? '' : '/r/$subreddit';
    final res = await _client.get<Map<String, dynamic>>(
      '$base/${sort.path}',
      query: {
        'limit': limit,
        if (after != null) 'after': after,
        if (sort.needsTime) 't': time.param,
      },
    );
    return _parsePostListing(res.data!);
  }

  /// Returns the post (refreshed) and its top-level comment tree.
  Future<(Post, List<Comment>)> getComments({
    required String subreddit,
    required String postId,
    String sort = 'confidence',
  }) async {
    // `_` (or empty) means the subreddit is unknown (e.g. a redd.it short link);
    // Reddit resolves the post from just the id.
    final unknown = subreddit.isEmpty || subreddit == '_';
    final path =
        unknown ? '/comments/$postId' : '/r/$subreddit/comments/$postId';
    final res = await _client.get<List<dynamic>>(
      path,
      query: {'sort': sort, 'limit': 100},
    );
    final body = res.data!;
    final postData =
        (((body[0] as Map)['data'] as Map)['children'] as List).first;
    final post = Post.fromData((postData as Map)['data'] as Map<String, dynamic>);
    final commentChildren =
        ((body[1] as Map)['data'] as Map)['children'] as List;
    final comments = [
      for (final c in commentChildren)
        Comment.fromChild(c as Map<String, dynamic>, 0)
    ];
    return (post, comments);
  }

  /// Expands a "load more comments" node.
  Future<List<Comment>> getMoreComments({
    required String linkFullname, // t3_xxx
    required List<String> childrenIds,
    String sort = 'confidence',
    int depth = 0,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/api/morechildren',
      query: {
        'api_type': 'json',
        'link_id': linkFullname,
        'children': childrenIds.join(','),
        'sort': sort,
        'limit_children': false,
      },
    );
    final things = (((res.data?['json'] as Map?)?['data'] as Map?)?['things']
            as List?) ??
        const [];
    // morechildren returns a flat list; we render them at the requested depth.
    return [
      for (final t in things)
        Comment.fromChild(t as Map<String, dynamic>, depth)
    ];
  }

  Future<Subreddit> getSubredditAbout(String name) async {
    final res =
        await _client.get<Map<String, dynamic>>('/r/$name/about');
    return Subreddit.fromData(res.data!['data'] as Map<String, dynamic>);
  }

  Future<RedditUser> getUserAbout(String username) async {
    final res =
        await _client.get<Map<String, dynamic>>('/user/$username/about');
    return RedditUser.fromData(res.data!['data'] as Map<String, dynamic>);
  }

  /// [where] ∈ submitted | upvoted | downvoted | hidden  (post listings)
  Future<Listing<Post>> getUserPosts(String username,
      {String where = 'submitted', String? after}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/user/$username/$where',
      query: {'limit': 25, if (after != null) 'after': after},
    );
    return _parsePostListing(res.data!);
  }

  Future<Listing<Comment>> getUserComments(String username,
      {String? after}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/user/$username/comments',
      query: {'limit': 25, if (after != null) 'after': after},
    );
    final data = res.data?['data'] as Map<String, dynamic>?;
    final children = (data?['children'] as List?) ?? const [];
    return Listing(
      items: [
        for (final c in children)
          if ((c as Map)['kind'] == 't1')
            Comment.fromChild(c as Map<String, dynamic>, 0),
      ],
      after: data?['after'] as String?,
    );
  }

  /// Saved items are mixed posts (t3) and comments (t1); items are [Post] or
  /// [Comment] in original order.
  Future<Listing<Object>> getUserSaved(String username, {String? after}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/user/$username/saved',
      query: {'limit': 25, if (after != null) 'after': after},
    );
    final data = res.data?['data'] as Map<String, dynamic>?;
    final children = (data?['children'] as List?) ?? const [];
    return Listing(
      items: [
        for (final c in children)
          if ((c as Map)['kind'] == 't3')
            Post.fromData(c['data'] as Map<String, dynamic>)
          else if (c['kind'] == 't1')
            Comment.fromChild(c as Map<String, dynamic>, 0),
      ],
      after: data?['after'] as String?,
    );
  }

  Future<Listing<Post>> searchPosts(String query,
      {String? subreddit, String? after, String sort = 'relevance'}) async {
    final base = subreddit == null ? '/search' : '/r/$subreddit/search';
    final res = await _client.get<Map<String, dynamic>>(
      base,
      query: {
        'q': query,
        'type': 'link',
        'sort': sort,
        'limit': 25,
        if (subreddit != null) 'restrict_sr': true,
        if (after != null) 'after': after,
      },
    );
    return _parsePostListing(res.data!);
  }

  Future<List<Subreddit>> searchSubreddits(String query) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/subreddits/search',
      query: {'q': query, 'limit': 25},
    );
    final children =
        ((res.data?['data'] as Map?)?['children'] as List?) ?? const [];
    return [
      for (final c in children)
        Subreddit.fromData((c as Map)['data'] as Map<String, dynamic>)
    ];
  }

  Future<List<RedditUser>> searchUsers(String query) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/search',
      query: {'q': query, 'type': 'user', 'limit': 25},
    );
    final children =
        ((res.data?['data'] as Map?)?['children'] as List?) ?? const [];
    return [
      for (final c in children)
        RedditUser.fromData((c as Map)['data'] as Map<String, dynamic>)
    ];
  }

  Future<List<Subreddit>> getSubscribedSubreddits() async {
    final result = <Subreddit>[];
    String? after;
    // Reddit caps at 100/page; loop a few pages for heavy subscribers.
    for (var i = 0; i < 5; i++) {
      final res = await _client.get<Map<String, dynamic>>(
        '/subreddits/mine/subscriber',
        query: {'limit': 100, if (after != null) 'after': after},
      );
      final data = res.data?['data'] as Map<String, dynamic>?;
      final children = (data?['children'] as List?) ?? const [];
      for (final c in children) {
        result.add(Subreddit.fromData((c as Map)['data'] as Map<String, dynamic>));
      }
      after = data?['after'] as String?;
      if (after == null) break;
    }
    // Favorites first, then alphabetical.
    result.sort((a, b) {
      if (a.userHasFavorited != b.userHasFavorited) {
        return a.userHasFavorited ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  Future<void> setSubredditFavorite(String subredditName, bool favorite) async {
    await _client.post('/api/favorite',
        data: {'sr_name': subredditName, 'make_favorite': '$favorite'});
  }

  // --- Moderation (requires mod permission on the thing's subreddit) ---

  Future<void> modApprove(String fullname) =>
      _client.post('/api/approve', data: {'id': fullname});

  Future<void> modRemove(String fullname, {bool spam = false}) =>
      _client.post('/api/remove', data: {'id': fullname, 'spam': '$spam'});

  Future<void> modLock(String fullname, bool lock) =>
      _client.post(lock ? '/api/lock' : '/api/unlock', data: {'id': fullname});

  /// distinguish: 'yes' (mod), 'no', or 'admin'. [sticky] pins a top comment.
  Future<void> modDistinguish(String fullname,
          {String how = 'yes', bool sticky = false}) =>
      _client.post('/api/distinguish',
          data: {'id': fullname, 'how': how, 'sticky': '$sticky', 'api_type': 'json'});

  /// dir: 1 upvote, -1 downvote, 0 clear.
  Future<void> vote(String fullname, int dir) async {
    await _client.post('/api/vote', data: {'id': fullname, 'dir': '$dir', 'rank': '10'});
  }

  Future<void> setSubscribed(String subredditName, bool subscribe) async {
    await _client.post('/api/subscribe', data: {
      'action': subscribe ? 'sub' : 'unsub',
      'sr_name': subredditName,
    });
  }

  Future<void> setSaved(String fullname, bool saved) async {
    await _client.post(saved ? '/api/save' : '/api/unsave',
        data: {'id': fullname});
  }

  // --- Participate: reply / submit / edit / delete ---

  List<String> _apiErrors(dynamic body) {
    final errors = ((body?['json'] as Map?)?['errors'] as List?) ?? const [];
    return [
      for (final e in errors)
        (e is List && e.length > 1) ? '${e[1]}' : '$e',
    ];
  }

  /// Posts a reply to [parentFullname] (a t3_ post or t1_ comment). Returns the
  /// created comment, ready to splice into the tree at [depth].
  Future<Comment> reply({
    required String parentFullname,
    required String text,
    int depth = 0,
  }) async {
    final res = await _client.post<Map<String, dynamic>>('/api/comment',
        data: {'api_type': 'json', 'thing_id': parentFullname, 'text': text});
    final errors = _apiErrors(res.data);
    if (errors.isNotEmpty) throw Exception(errors.first);
    final things =
        (((res.data?['json'] as Map)['data'] as Map)['things'] as List);
    return Comment.fromChild(things.first as Map<String, dynamic>, depth);
  }

  /// Edits the body of your own post (selftext) or comment. Returns new body.
  Future<String> editText({
    required String thingFullname,
    required String text,
  }) async {
    final res = await _client.post<Map<String, dynamic>>('/api/editusertext',
        data: {'api_type': 'json', 'thing_id': thingFullname, 'text': text});
    final errors = _apiErrors(res.data);
    if (errors.isNotEmpty) throw Exception(errors.first);
    return text;
  }

  Future<void> deleteThing(String fullname) async {
    await _client.post('/api/del', data: {'id': fullname});
  }

  /// Submits a text or link post. For image posts, upload first with
  /// [uploadImage] and pass the resulting URL with [kind] = 'image'.
  /// Returns the new post id so the UI can open it.
  Future<String> submitPost({
    required String subreddit,
    required String title,
    required String kind, // 'self' | 'link' | 'image'
    String? text,
    String? url,
    bool nsfw = false,
    bool spoiler = false,
    bool sendReplies = true,
    Flair? flair,
  }) async {
    final res = await _client.post<Map<String, dynamic>>('/api/submit', data: {
      'api_type': 'json',
      'sr': subreddit,
      'title': title,
      'kind': kind,
      if (kind == 'self') 'text': text ?? '',
      if (kind == 'link' || kind == 'image') ...{
        'url': url ?? '',
        if (text != null && text.isNotEmpty) 'text': text,
      },
      if (flair != null) 'flair_id': flair.id,
      if (flair != null) 'flair_text': flair.text,
      'nsfw': '$nsfw',
      'spoiler': '$spoiler',
      'sendreplies': '$sendReplies',
    });
    final errors = _apiErrors(res.data);
    if (errors.isNotEmpty) throw Exception(errors.first);
    final data = (res.data?['json'] as Map)['data'] as Map?;
    final id = data?['id'] as String?;
    if (id == null) throw Exception('Reddit did not return the new post.');
    return id;
  }

  // --- Inbox / messages ---

  /// [where] ∈ inbox | unread | messages | sent | comments | mentions
  Future<Listing<InboxItem>> getInbox(
      {String where = 'inbox', String? after}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/message/$where',
      query: {'limit': 25, if (after != null) 'after': after},
    );
    final data = res.data?['data'] as Map<String, dynamic>?;
    final children = (data?['children'] as List?) ?? const [];
    return Listing(
      items: [
        for (final c in children)
          InboxItem.fromChild(c as Map<String, dynamic>),
      ],
      after: data?['after'] as String?,
    );
  }

  Future<int> getUnreadCount() async {
    final listing = await getInbox(where: 'unread');
    return listing.items.length;
  }

  Future<void> markRead(String fullname) async {
    await _client.post('/api/read_message', data: {'id': fullname});
  }

  Future<void> markAllRead() async {
    await _client.post('/api/read_all_messages');
  }

  /// Replies to a message or inbox comment (thing_id = t4_/t1_ fullname).
  Future<void> sendReply(String parentFullname, String text) async {
    final res = await _client.post<Map<String, dynamic>>('/api/comment',
        data: {'api_type': 'json', 'thing_id': parentFullname, 'text': text});
    final errors = _apiErrors(res.data);
    if (errors.isNotEmpty) throw Exception(errors.first);
  }

  Future<void> composeMessage({
    required String to,
    required String subject,
    required String text,
  }) async {
    final res = await _client.post<Map<String, dynamic>>('/api/compose',
        data: {'api_type': 'json', 'to': to, 'subject': subject, 'text': text});
    final errors = _apiErrors(res.data);
    if (errors.isNotEmpty) throw Exception(errors.first);
  }

  /// Uploads media bytes to Reddit's media store. Two-step: lease from Reddit,
  /// then S3 PUT. Returns the public S3 [url] (for link/image/video posts) and
  /// the [assetId] (= media_id, required for gallery submission).
  Future<({String url, String assetId})> uploadMediaAsset({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final lease = await _client.post<Map<String, dynamic>>(
      '/api/media/asset.json',
      data: {'filepath': filename, 'mimetype': mimeType},
    );
    final args = (lease.data?['args'] as Map?);
    final action = args?['action'] as String?;
    final fields = (args?['fields'] as List?) ?? const [];
    final assetId = ((lease.data?['asset'] as Map?)?['asset_id'] as String?) ?? '';
    if (action == null) throw Exception('Could not get an upload lease.');

    final form = FormData();
    for (final f in fields) {
      form.fields.add(MapEntry((f as Map)['name'] as String, '${f['value']}'));
    }
    form.files.add(MapEntry(
      'file',
      MultipartFile.fromBytes(bytes, filename: filename),
    ));

    final uploadUrl = action.startsWith('http') ? action : 'https:$action';
    final s3 = Dio();
    final res = await s3.post(uploadUrl, data: form);
    final xml = res.data is String ? res.data as String : '${res.data}';
    final match = RegExp(r'<Location>(.*?)</Location>').firstMatch(xml);
    final location = match?.group(1)?.replaceAll('&amp;', '&');
    if (location == null) throw Exception('Upload failed (no location).');
    return (url: location, assetId: assetId);
  }

  Future<String> uploadImage({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final r = await uploadMediaAsset(
        bytes: bytes, filename: filename, mimeType: mimeType);
    return r.url;
  }

  // --- Post actions: hide / report / crosspost ---

  Future<void> setHidden(String fullname, bool hidden) async {
    await _client.post(hidden ? '/api/hide' : '/api/unhide',
        data: {'id': fullname});
  }

  Future<void> report(String fullname, String reason) async {
    await _client.post('/api/report',
        data: {'thing_id': fullname, 'reason': reason});
  }

  Future<String> submitCrosspost({
    required String subreddit,
    required String title,
    required String crosspostFullname,
    bool nsfw = false,
    bool spoiler = false,
  }) async {
    final res = await _client.post<Map<String, dynamic>>('/api/submit', data: {
      'api_type': 'json',
      'sr': subreddit,
      'title': title,
      'kind': 'crosspost',
      'crosspost_fullname': crosspostFullname,
      'nsfw': '$nsfw',
      'spoiler': '$spoiler',
      'sendreplies': 'true',
    });
    final errors = _apiErrors(res.data);
    if (errors.isNotEmpty) throw Exception(errors.first);
    final id = ((res.data?['json'] as Map)['data'] as Map?)?['id'] as String?;
    if (id == null) throw Exception('Crosspost failed.');
    return id;
  }

  // --- Flair ---

  Future<List<Flair>> getLinkFlairs(String subreddit) async {
    try {
      final res =
          await _client.get<List<dynamic>>('/r/$subreddit/api/link_flair');
      return [
        for (final f in res.data ?? const [])
          Flair.fromJson(f as Map<String, dynamic>),
      ].where((f) => f.text.isNotEmpty).toList();
    } catch (_) {
      return const []; // subreddit may have no flairs / no permission
    }
  }

  // --- Gallery & video submission ---

  /// Submits a gallery post from already-uploaded media ids (asset_ids).
  Future<void> submitGalleryPost({
    required String subreddit,
    required String title,
    required List<String> mediaIds,
    String text = '',
    bool nsfw = false,
    bool spoiler = false,
    bool sendReplies = true,
    Flair? flair,
  }) async {
    final body = {
      'sr': subreddit,
      'submit_type': 'subreddit',
      'api_type': 'json',
      'show_error_list': true,
      'title': title,
      'text': text,
      'spoiler': spoiler,
      'nsfw': nsfw,
      'kind': 'self',
      'original_content': false,
      'post_to_twitter': false,
      'sendreplies': sendReplies,
      'validate_on_submit': true,
      if (flair != null) 'flair_id': flair.id,
      if (flair != null) 'flair_text': flair.text,
      'items': [
        for (final id in mediaIds)
          {'caption': '', 'outbound_url': '', 'media_id': id},
      ],
    };
    final res = await _client.postJson<Map<String, dynamic>>(
        '/api/submit_gallery_post.json',
        data: body);
    final errors = _apiErrors(res.data);
    if (errors.isNotEmpty) throw Exception(errors.first);
  }

  /// Submits a video (or video-gif) post. [videoUrl] and [posterUrl] are S3
  /// URLs returned by [uploadMediaAsset].
  Future<String> submitVideoPost({
    required String subreddit,
    required String title,
    required String videoUrl,
    required String posterUrl,
    bool isGif = false,
    String text = '',
    bool nsfw = false,
    bool spoiler = false,
    bool sendReplies = true,
    Flair? flair,
  }) async {
    final res = await _client.post<Map<String, dynamic>>('/api/submit', data: {
      'api_type': 'json',
      'sr': subreddit,
      'title': title,
      'kind': isGif ? 'videogif' : 'video',
      'url': videoUrl,
      'video_poster_url': posterUrl,
      if (text.isNotEmpty) 'text': text,
      if (flair != null) 'flair_id': flair.id,
      if (flair != null) 'flair_text': flair.text,
      'nsfw': '$nsfw',
      'spoiler': '$spoiler',
      'sendreplies': '$sendReplies',
    });
    final errors = _apiErrors(res.data);
    if (errors.isNotEmpty) throw Exception(errors.first);
    final id = ((res.data?['json'] as Map)['data'] as Map?)?['id'] as String?;
    return id ?? '';
  }

  // --- Multireddits ---

  Future<List<Multireddit>> getMyMultireddits() async {
    final res = await _client
        .get<List<dynamic>>('/api/multi/mine', query: {'expand_srs': true});
    return [
      for (final m in res.data ?? const [])
        Multireddit.fromData((m as Map)['data'] as Map<String, dynamic>),
    ]..sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  }

  Future<Listing<Post>> getMultiPosts({
    required String username,
    required String multiname,
    PostSort sort = PostSort.hot,
    TopTime time = TopTime.day,
    String? after,
    int limit = 25,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/user/$username/m/$multiname/${sort.path}',
      query: {
        'limit': limit,
        if (after != null) 'after': after,
        if (sort.needsTime) 't': time.param,
      },
    );
    return _parsePostListing(res.data!);
  }

  Future<void> createMultireddit({
    required String username,
    required String name,
    List<String> subreddits = const [],
    String visibility = 'private',
    String description = '',
  }) async {
    final multipath = '/user/$username/m/$name';
    final model = jsonEncode({
      'display_name': name,
      'subreddits': [for (final s in subreddits) {'name': s}],
      'visibility': visibility,
      'description_md': description,
    });
    final res = await _client.post<Map<String, dynamic>>('/api/multi$multipath',
        data: {'model': model, 'multipath': multipath, 'api_type': 'json'});
    final errors = _apiErrors(res.data);
    if (errors.isNotEmpty) throw Exception(errors.first);
  }

  Future<void> deleteMultireddit(String multipath) async {
    await _client.delete('/api/multi$multipath');
  }

  Future<void> addSubredditToMulti(String multipath, String subreddit) async {
    await _client.put('/api/multi$multipath/r/$subreddit',
        data: jsonEncode({'name': subreddit}));
  }

  Future<void> removeSubredditFromMulti(
      String multipath, String subreddit) async {
    await _client.delete('/api/multi$multipath/r/$subreddit');
  }
}
