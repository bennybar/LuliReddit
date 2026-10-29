// Website sign-in: Reddit's edge refuses the website's search endpoints and
// /by_id (403), so search and posts by id (Reddit Home, Blend) run on
// Reddit's app GraphQL API, as Reddit's own apps and other clients (e.g.
// Hydra) do. Its operations are persisted queries, run by
// name and the hash of the query Reddit already knows.
const gqlSearchPosts =
    'c3d31b88bfa15180fdcd0c8f6f13b8c0e131d0c981c9b9c8a7c537ddd0ed3348';
const gqlSearchCommunities =
    'b58025ad0c98bdb93e9dc1db909accf440573bd7d3a48d2c73a02e96d33f1943';
const gqlSearchPeople =
    'db3607c1a7deea8441614a053c5f434f60da0c8c931db952f819a59d534d9743';
const gqlPostsByIds =
    'b210ea1d852cdc2c25d9bff2d9fa8a406e1a968f36392798812f336694ac27f4';

/// A post (not an ad or an unavailable one) in GraphQL's results.
bool gqlIsPost(Map n) => const {
      'SubredditPost',
      'ProfilePost',
      'DeletedSubredditPost'
    }.contains(n['__typename']);

// The post fragment's switches, as Reddit's app sets them for full posts.
const gqlPostFlags = {
  'includeSubredditInPosts': true,
  'includeAwards': true,
  'includePostStats': true,
  'includeCurrentUserAwards': false,
  'includeStillMediaAltText': true,
  'includeExtraStillResolutions': true,
  'includeExtendedVideoAsset': false,
  'includePlaybackMp4s': true,
  'includeMuxedMp4s': true,
  'includeDevvitData': true,
  'includeCommunityStatus': true,
  'includeIsModRemovedContentReadAllowed': true,
  'includeVideoPlaybackInComments': false,
  'includeSubredditBackgroundColor': true,
  'includeOverlayData': true,
  'includeCtaEnrichedPageTitle': true,
  'includePlaCards': true,
  'includePlaCardThumbnail': false,
  'includeWebviewPrefetchField': true,
  'includeAdBrowserDestinationField': true,
  'includeCollectionsHeroCard': true,
  'includeGalleryAdUrl': true,
  'includeCtaMediaColor': true,
  'includeFollowedForNotificationsStatus': true,
  'includePredictedRemovalReasons': true,
  'includeRedditHandleInfo': true,
  'includeVerificationStatus': true,
  'skipModerationInfo': false,
  'includeIsReceivingPostReplies': false,
  'includeIsActiveComments': true,
  'includeMediaSynthesis': true,
  'skipRedditPlayPlaybackMp4s': true,
  'includeLinkPreviewTitle': false,
};

const gqlSorts = {
  'relevance': 'RELEVANCE',
  'hot': 'HOT',
  'new': 'NEW',
  'top': 'TOP',
  'comments': 'COMMENTS',
};

/// One kind of search result (posts, communities, authors): its nodes, and
/// the next page's cursor (null at the end).
({List<Map> nodes, String? after}) gqlSearch(
    Map<String, dynamic> data, String kind) {
  final list = (((data['search'] as Map?)?['general'] as Map?)?[kind]) as Map?;
  final info = list?['pageInfo'] as Map?;
  return (
    nodes: [
      for (final e in (list?['edges'] as List?) ?? const [])
        if ((e as Map?)?['node'] is Map) e!['node'] as Map
    ],
    after: info?['hasNextPage'] == false ? null : info?['endCursor'] as String?,
  );
}

/// A GraphQL post (search, PostsByIds) in the shape Post.fromData reads
/// (Reddit's listing JSON): what a card shows, with its media. Opening it
/// loads the full post.
Map<String, dynamic> gqlPostData(Map n) {
  final id = '${n['id']}'.replaceFirst('t3_', '');
  final community = (n['subreddit'] ?? n['profile']) as Map?;
  final sub = community?['name'] as String? ?? '';
  final url = n['url'] as String? ?? '';
  final host = Uri.tryParse(url)?.host ?? '';
  final isSelf = n['isSelfPost'] == true;
  // The image (a gallery's first) at each size, smallest first.
  ({String url, int? width, int? height})? size(Object? s) {
    final m = s as Map?;
    final u = m?['url'] as String?;
    final dims = m?['dimensions'] as Map?;
    return u == null
        ? null
        : (
            url: u,
            width: (dims?['width'] as num?)?.toInt(),
            height: (dims?['height'] as num?)?.toInt());
  }
  final still = (n['media'] as Map?)?['still'] as Map?;
  final asset = ((((n['gallery'] as Map?)?['items'] as List?)?.firstOrNull)
      as Map?)?['media'] as Map?;
  final sizes = [
    if (still != null)
      for (final k in const ['small', 'medium', 'large', 'midlarge480',
          'xlarge', 'xlargePlus720', 'xxlarge', 'xxxlarge', 'source'])
        size(still[k]),
    if (asset != null) ...[
      for (final k in const ['small', 'medium', 'large', 'xlarge', 'xxlarge',
          'xxxlarge'])
        size(asset[k]),
      size({
        'url': asset['url'],
        'dimensions': {'width': asset['width'], 'height': asset['height']},
      }),
    ],
  ].nonNulls.toList();
  Map<String, dynamic> image(({String url, int? width, int? height}) s) =>
      {'url': s.url, 'width': s.width, 'height': s.height};
  final media = n['media'] as Map?;
  final hls = (media?['streaming'] as Map?)?['hlsUrl'] as String?;
  final animated = media?['animated'] as Map?;
  final gifMp4 = ((animated?['mp4_source'] ?? animated?['mp4_xxxlarge'])
      as Map?)?['url'] as String?;
  // Every gallery image, as gallery_data + media_metadata.
  final galleryItems = [
    for (final item in ((n['gallery'] as Map?)?['items'] as List?) ?? const [])
      if (((item as Map?)?['media'] as Map?)?['url'] is String)
        item!['media'] as Map
  ];
  final root = (n['crosspostRoot'] as Map?)?['post'] as Map?;
  final icon = (community?['styles'] as Map?)?['icon'] as String? ??
      (((community?['styles'] as Map?)?['legacyIcon'] as Map?)?['url']
          as String?);
  final vote = switch (n['voteState']) { 'UP' => true, 'DOWN' => false, _ => null };
  return {
    'id': id,
    'name': n['id'],
    'title': n['postTitle'] ?? n['title'] ?? '',
    'author': (n['authorInfo'] as Map?)?['name'] ?? '[deleted]',
    'subreddit': sub,
    'subreddit_name_prefixed': community?['prefixedName'] ?? 'r/$sub',
    'score': (n['score'] as num?)?.toInt() ?? 0,
    'num_comments': (n['commentCount'] as num?)?.toInt() ?? 0,
    'created_utc': (DateTime.tryParse('${n['createdAt']}')
                ?.millisecondsSinceEpoch ??
            0) /
        1000,
    'permalink': n['permalink'] ?? '/r/$sub/comments/$id/',
    'url': url,
    'domain': isSelf ? 'self.$sub' : host,
    'is_self': isSelf,
    'is_video': host == 'v.redd.it',
    'selftext': (n['content'] as Map?)?['markdown'] ?? '',
    'over_18': n['isNsfw'] ?? false,
    'spoiler': n['isSpoiler'] ?? false,
    'stickied': n['isStickied'] ?? false,
    'locked': n['isLocked'] ?? false,
    'saved': n['isSaved'] ?? false,
    'likes': vote,
    'link_flair_text': (n['flair'] as Map?)?['text'],
    'thumbnail': sizes.isEmpty ? (isSelf ? 'self' : 'default') : sizes.first.url,
    'post_hint': sizes.isEmpty
        ? null
        : host == 'i.redd.it'
            ? 'image'
            : host == 'v.redd.it'
                ? 'hosted:video'
                : 'link',
    if (icon != null) 'sr_detail': {'icon_img': icon.split('?').first},
    if (hls != null)
      'media': {
        'reddit_video': {
          'hls_url': hls,
          'is_gif': (media?['streaming'] as Map?)?['isGif'] == true,
        },
      },
    if (galleryItems.isNotEmpty) ...{
      'gallery_data': {
        'items': [
          for (var i = 0; i < galleryItems.length; i++) {'media_id': 'g$i'}
        ],
      },
      'media_metadata': {
        for (var i = 0; i < galleryItems.length; i++)
          'g$i': {
            's': {
              'u': galleryItems[i]['url'],
              'x': galleryItems[i]['width'],
              'y': galleryItems[i]['height'],
            },
          },
      },
    },
    if (root != null && root['id'] != n['id'])
      'crosspost_parent_list': [gqlPostData(root)],
    if (sizes.isNotEmpty || gifMp4 != null)
      'preview': {
        if (sizes.isNotEmpty)
          'images': [
            {
              'source': image(sizes.last),
              'resolutions': [for (final s in sizes) image(s)],
            }
          ],
        if (gifMp4 != null) 'reddit_video_preview': {'fallback_url': gifMp4},
      },
  };
}
