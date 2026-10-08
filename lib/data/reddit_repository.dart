import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/network/catbox.dart';
import '../core/network/reddit_client.dart';
import '../features/foryou/for_you_ranker.dart';
import '../features/foryou/for_you_stores.dart' show ForYouMeta;
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

  // Short-lived cache of the subscription list — it's expensive (up to 5
  // sequential paged requests) and is hit on every "For You" build.
  // Config is pushed in from settings via redditRepositoryProvider.
  List<Subreddit>? _subsCache;
  DateTime? _subsCacheAt;
  bool subsCacheEnabled = true;
  Duration subsCacheTtl = const Duration(minutes: 10);

  Listing<Post> _parsePostListing(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>?;
    final children = (data?['children'] as List?) ?? const [];
    final posts = <Post>[];
    for (final c in children) {
      final kind = (c as Map)['kind'];
      if (kind == 't3') {
        final raw = c['data'] as Map<String, dynamic>;
        final post = Post.fromData(raw);
        posts.add(post);
        _rawPosts.remove(post.id);
        _rawPosts[post.id] = raw;
      }
    }
    while (_rawPosts.length > 800) {
      _rawPosts.remove(_rawPosts.keys.first);
    }
    return Listing(items: posts, after: data?['after'] as String?);
  }

  // The raw JSON of recently parsed posts (bounded), so a ranked For You
  // page can be saved and painted instantly next time.
  final _rawPosts = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? rawPost(String id) => _rawPosts[id];

  /// "For You (Beta)" — a transparent, client-side personalized feed.
  ///
  /// Reddit's real Home ranking is server-side ML and is NOT exposed to the
  /// API, so this approximates it: fetch candidates from the sources that
  /// matter to the user, then rank them on-device ([rankForYou]).
  ///
  /// Candidates: /best (subscriptions; paginated), rising and r/popular
  /// (paginated), and on the first page hot posts from favourites, the most
  /// engaged communities and a few [communities] the user has visited.
  /// [carryOver] is the previous page's unplaced pool.
  Future<ForYouPage> getForYouFeed({
    required RankInputs inputs,
    List<String> communities = const [],
    String? cursors, // JSON cursor bundle from a previous page's `after`
    Set<String> excludeIds = const {},
    List<Candidate> carryOver = const [],
  }) async {
    Map<String, dynamic> prev = const {};
    if (cursors != null && cursors.isNotEmpty) {
      try {
        prev = jsonDecode(cursors) as Map<String, dynamic>;
      } catch (_) {}
    }
    ForYouPage? page;
    // An empty page (everything failed, or all muted/seen) retries the next
    // cursors once before ending the feed — it used to stop dead.
    for (var attempt = 0; attempt < 2; attempt++) {
      page = await _forYouPage(inputs, communities, prev, excludeIds,
          attempt == 0 ? carryOver : const []);
      if (page.listing.items.isNotEmpty || page.cursors.isEmpty) break;
      prev = page.cursors;
    }
    return page!;
  }

  Future<ForYouPage> _forYouPage(
    RankInputs inputs,
    List<String> communities,
    Map<String, dynamic> prev,
    Set<String> excludeIds,
    List<Candidate> carryOver,
  ) async {
    final firstPage = prev.isEmpty;
    final muted = inputs.muted;

    // Subreddits you engage with most (learned on-device), even if not
    // favourited. Local data, so known before any request goes out.
    final topInterest = (inputs.interest.entries
            .where((e) => e.value >= kEngagedInterest && !muted.contains(e.key))
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .map((e) => e.key)
        .toList();

    // Each source: its listing, or null if it failed / timed out. Secondary
    // sources get a short timeout so the slowest community doesn't decide how
    // long the page takes.
    Future<Listing<Post>?> source(Future<Listing<Post>> f,
            {bool secondary = true}) =>
        (secondary ? f.timeout(const Duration(milliseconds: 2500)) : f)
            .then<Listing<Post>?>((l) => l)
            .catchError((_) => null);

    // A cursor of '' means "start this source from the top" (its first
    // fetch failed); a missing key means the source is exhausted.
    bool live(String k) => firstPage || prev.containsKey(k);
    String? after(String k) {
      final v = prev[k] as String?;
      return (v == null || v.isEmpty) ? null : v;
    }

    final subsF = getSubscribedSubreddits()
        .catchError((_) => const <Subreddit>[]);
    final bestF = live('best')
        ? source(
            getPosts(
                sort: PostSort.best,
                limit: firstPage ? 100 : 50,
                after: after('best')),
            secondary: false)
        : Future<Listing<Post>?>.value(null);
    final risingF = live('rising')
        ? source(getPosts(sort: PostSort.rising, limit: 25, after: after('rising')))
        : Future<Listing<Post>?>.value(null);
    final popularF = live('popular')
        ? source(getPosts(
            subreddit: 'popular',
            sort: PostSort.hot,
            limit: firstPage ? 20 : 15,
            after: after('popular')))
        : Future<Listing<Post>?>.value(null);
    final interestF = [
      if (firstPage)
        for (final s in topInterest)
          source(getPosts(subreddit: s, sort: PostSort.hot, limit: 8)),
    ];
    final communityF = [
      if (firstPage)
        for (final s in communities.where((c) => !muted.contains(c)))
          source(getPosts(subreddit: s, sort: PostSort.hot, limit: 6)),
    ];

    final mySubs = await subsF;
    final favourites = {
      for (final s in mySubs)
        if (s.userHasFavorited) s.name.toLowerCase()
    };
    final subscribed = {for (final s in mySubs) s.name.toLowerCase()};
    // Favourites go out the moment the list is known, while the rest is still
    // in flight. One already fetched as a top interest isn't fetched twice.
    final favouriteF = [
      if (firstPage)
        for (final f in favourites.take(8))
          if (!topInterest.contains(f) && !muted.contains(f))
            source(getPosts(subreddit: f, sort: PostSort.hot, limit: 10)),
    ];

    final best = await bestF, rising = await risingF, popular = await popularF;
    final ids = <String>{...excludeIds};
    final pool = <Candidate>[];
    void add(Listing<Post>? l, String src) {
      for (final p in l?.items ?? const <Post>[]) {
        if (ids.add(p.id)) pool.add(Candidate(p, src));
      }
    }

    for (final c in carryOver) {
      if (ids.add(c.post.id)) pool.add(Candidate(c.post, 'carry'));
    }
    add(best, 'best');
    add(rising, 'rising');
    add(popular, 'popular');
    for (final l in await Future.wait(favouriteF)) {
      add(l, 'favourite');
    }
    for (final l in await Future.wait(interestF)) {
      add(l, 'interest');
    }
    for (final l in await Future.wait(communityF)) {
      add(l, 'community');
    }

    final result = rankForYou(
        pool, inputs.withSubscriptions(favourites, subscribed));

    // Next cursors. A source that failed keeps its place (it used to be
    // dropped for the rest of the session — one timeout on /best and the
    // feed quietly became r/popular); an exhausted one is left out.
    final next = <String, String>{};
    for (final (key, listing) in [
      ('best', best),
      ('rising', rising),
      ('popular', popular),
    ]) {
      if (!live(key)) continue;
      if (listing == null) {
        next[key] = (prev[key] as String?) ?? '';
      } else if ((listing.after ?? '').isNotEmpty) {
        next[key] = listing.after!;
      }
    }
    return ForYouPage(
      listing: Listing(
        items: result.ranked,
        after: (result.ranked.isNotEmpty || result.leftovers.isNotEmpty) &&
                next.isNotEmpty
            ? jsonEncode(next)
            : null,
      ),
      cursors: next,
      leftovers: result.leftovers,
      meta: result.meta,
      candidateTitles: [for (final c in pool) c.post.title],
    );
  }

  /// Posts by fullname (t3_…), in the order given. Reddit returns /by_id in
  /// its own order and drops removed posts, so the result is re-ordered.
  Future<List<Post>> getPostsByIds(List<String> fullnames) async {
    if (fullnames.isEmpty) return const [];
    final res = await _client.get<Map<String, dynamic>>(
        '/by_id/${fullnames.join(',')}',
        query: {'limit': fullnames.length});
    final byId = {
      for (final p in _parsePostListing(res.data!).items) 't3_${p.id}': p
    };
    return [
      for (final f in fullnames)
        if (byId[f] != null) byId[f]!
    ];
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

  /// The last cached first page for exactly this feed, or null. Used to paint
  /// instantly while the fresh page is still in flight.
  Future<Listing<Post>?> cachedPosts({
    String? subreddit,
    PostSort sort = PostSort.best,
    TopTime time = TopTime.day,
    int limit = 25,
  }) async {
    final base = subreddit == null ? '' : '/r/$subreddit';
    final json = await _client.cached(
      '$base/${sort.path}',
      query: {
        'limit': limit,
        if (sort.needsTime) 't': time.param,
      },
    );
    if (json is! Map<String, dynamic>) return null;
    final listing = _parsePostListing(json);
    return listing.items.isEmpty ? null : listing;
  }

  /// Returns the post (refreshed) and its top-level comment tree.
  /// Returns the post, its comment tree and the thread's suggested comment
  /// sort (e.g. "qa" on AMAs), if the moderators set one.
  Future<(Post, List<Comment>, String?)> getComments({
    required String subreddit,
    required String postId,
    String sort = 'confidence',
    String? focusCommentId,
  }) async =>
      parseThread(await getCommentsRaw(
          subreddit: subreddit,
          postId: postId,
          sort: sort,
          focusCommentId: focusCommentId));

  /// The raw comments response — kept as-is for offline reading.
  Future<List<dynamic>> getCommentsRaw({
    required String subreddit,
    required String postId,
    String sort = 'confidence',
    String? focusCommentId,
    int limit = 100,
  }) async {
    // `_` (or empty) means the subreddit is unknown (e.g. a redd.it short link);
    // Reddit resolves the post from just the id.
    final unknown = subreddit.isEmpty || subreddit == '_';
    final path =
        unknown ? '/comments/$postId' : '/r/$subreddit/comments/$postId';
    final res = await _client.get<List<dynamic>>(
      path,
      query: {
        'sort': sort,
        'limit': limit,
        // Focus on a single comment (from a permalink / inbox reply): Reddit
        // returns that comment's thread, with a few parents for context.
        if (focusCommentId != null) ...{
          'comment': focusCommentId,
          'context': 3,
        },
      },
    );
    return res.data!;
  }

  /// Parses a comments response (live or saved offline).
  (Post, List<Comment>, String?) parseThread(List<dynamic> body) {
    final postChildren =
        (((body[0] as Map)['data'] as Map)['children'] as List);
    final postData =
        ((postChildren.first as Map)['data'] as Map).cast<String, dynamic>();
    final post = Post.fromData(postData);
    final suggested = postData['suggested_sort'] as String?;
    final commentChildren =
        ((body[1] as Map)['data'] as Map)['children'] as List;
    final comments = [
      for (final c in commentChildren)
        if (c is Map) Comment.fromChild(c.cast<String, dynamic>(), 0)
    ];
    return (post, comments, (suggested ?? '').isEmpty ? null : suggested);
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

  /// Subreddit rules as (title, description) pairs.
  Future<List<(String, String)>> getSubredditRules(String name) async {
    final res = await _client.get<Map<String, dynamic>>('/r/$name/about/rules');
    final rules = (res.data?['rules'] as List?) ?? const [];
    return [
      for (final r in rules)
        if (r is Map)
          (
            (r['short_name'] as String? ?? '').trim(),
            (r['description'] as String? ?? '').trim(),
          ),
    ];
  }

  Future<RedditUser> getUserAbout(String username) async {
    final res =
        await _client.get<Map<String, dynamic>>('/user/$username/about');
    return RedditUser.fromData(res.data!['data'] as Map<String, dynamic>);
  }

  /// [where] ∈ submitted | upvoted | downvoted | hidden  (post listings)
  Future<Listing<Post>> getUserPosts(String username,
      {String where = 'submitted', String? after, int limit = 25}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/user/$username/$where',
      query: {'limit': limit, if (after != null) 'after': after},
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
  Future<Listing<Object>> getUserSaved(String username,
      {String? after, int limit = 25}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/user/$username/saved',
      query: {'limit': limit, if (after != null) 'after': after},
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
      {String? subreddit,
      String? after,
      String sort = 'relevance',
      String time = 'all'}) async {
    final base = subreddit == null ? '/search' : '/r/$subreddit/search';
    final res = await _client.get<Map<String, dynamic>>(
      base,
      query: {
        'q': query,
        'type': 'link',
        'sort': sort,
        't': time,
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

  /// Drops the in-memory subscription cache (e.g. on account switch).
  void clearSubsCache() {
    _subsCache = null;
    _subsCacheAt = null;
  }

  Future<List<Subreddit>> getSubscribedSubreddits({bool force = false}) async {
    final cached = _subsCache;
    if (!force &&
        subsCacheEnabled &&
        cached != null &&
        _subsCacheAt != null &&
        DateTime.now().difference(_subsCacheAt!) < subsCacheTtl) {
      return cached;
    }
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
    _subsCache = result;
    _subsCacheAt = DateTime.now();
    return result;
  }

  Future<void> setSubredditFavorite(String subredditName, bool favorite) async {
    await _client.post('/api/favorite',
        data: {'sr_name': subredditName, 'make_favorite': '$favorite'});
    _subsCache = null; // favourite flag changed
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
    _subsCache = null; // subscription set changed
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
    String? richtextJson,
    int depth = 0,
  }) async {
    final res = await _client.post<Map<String, dynamic>>('/api/comment', data: {
      'api_type': 'json',
      'thing_id': parentFullname,
      if (richtextJson != null) 'richtext_json': richtextJson else 'text': text,
    });
    final errors = _apiErrors(res.data);
    if (errors.isNotEmpty) throw Exception(errors.first);
    final things =
        (((res.data?['json'] as Map)['data'] as Map)['things'] as List);
    return Comment.fromChild(things.first as Map<String, dynamic>, depth);
  }

  /// Posts a comment reply with an inline image, hosted by Reddit via the
  /// richtext API (the way the official app does it). Subreddits that disallow
  /// comment images will reject this, so we transparently fall back to hosting
  /// the image on Catbox and dropping a link into the comment instead.
  Future<Comment> replyWithImage({
    required String parentFullname,
    required String text,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    int depth = 0,
  }) async {
    try {
      final asset = await uploadMediaAsset(
          bytes: bytes, filename: filename, mimeType: mimeType);
      final doc = {
        'document': [
          if (text.isNotEmpty)
            {
              'e': 'par',
              'c': [
                {'e': 'text', 't': text}
              ]
            },
          {'e': 'img', 'id': asset.assetId},
        ],
      };
      return await reply(
        parentFullname: parentFullname,
        text: text,
        richtextJson: jsonEncode(doc),
        depth: depth,
      );
    } catch (_) {
      final url = await uploadToCatbox(bytes: bytes, filename: filename);
      final body = text.isEmpty ? url : '$text\n\n$url';
      return reply(parentFullname: parentFullname, text: body, depth: depth);
    }
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
      {String where = 'inbox', String? after, int limit = 25}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/message/$where',
      query: {'limit': limit, if (after != null) 'after': after},
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
    // One page of 100 (Reddit's max): the badge shows "99+" beyond that, so
    // the default page of 25 used to cap it at 25.
    final listing = await getInbox(where: 'unread', limit: 100);
    return listing.items.length;
  }

  Future<void> markRead(String fullname) async {
    await _client.post('/api/read_message', data: {'id': fullname});
  }

  Future<void> markAllRead() async {
    await _client.post('/api/read_all_messages');
  }

  Future<void> markUnread(String fullname) async {
    await _client.post('/api/unread_message', data: {'id': fullname});
  }

  /// Deletes a private message from the inbox (t4_ only; you can't delete
  /// comment replies).
  Future<void> deleteMessage(String fullname) async {
    await _client.post('/api/del_msg', data: {'id': fullname});
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

  /// Blocks a user (you stop seeing their posts/comments/messages).
  Future<void> blockUser(String username) async {
    await _client.post('/api/block_user', data: {'name': username});
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

/// One page of For You, plus what the next page and the UI need.
class ForYouPage {
  const ForYouPage({
    required this.listing,
    required this.cursors,
    required this.leftovers,
    required this.meta,
    required this.candidateTitles,
  });
  final Listing<Post> listing;
  final Map<String, String> cursors;
  final List<Candidate> leftovers;
  final Map<String, ForYouMeta> meta;
  final List<String> candidateTitles; // for word rarity (IDF)
}
