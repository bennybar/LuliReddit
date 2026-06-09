import 'package:freezed_annotation/freezed_annotation.dart';

part 'post.freezed.dart';

enum PostType { self, image, video, gif, gallery, link }

/// A gallery item (resolved image url + dimensions).
class GalleryImage {
  const GalleryImage({required this.url, this.width, this.height});
  final String url;
  final int? width;
  final int? height;
}

@freezed
class Post with _$Post {
  const Post._();

  const factory Post({
    required String id,
    required String fullname, // t3_xxx
    required String title,
    required String subreddit,
    required String subredditPrefixed,
    required String author,
    required int score,
    required int numComments,
    required double upvoteRatio,
    required DateTime created,
    required String permalink,
    required String url,
    required String domain,
    required PostType type,
    @Default(false) bool isSelf,
    @Default('') String selftext,
    @Default(false) bool over18,
    @Default(false) bool spoiler,
    @Default(false) bool stickied,
    @Default(false) bool locked,
    @Default(false) bool saved,
    @Default(false) bool canModPost,
    String? linkFlairText,
    String? distinguished,
    String? feedReason, // "why you're seeing this" in the For You feed (transient)
    String? crosspostFrom, // subreddit a crosspost originates from
    @Default(<String>[]) List<String> pollOptions,
    // media
    String? thumbnailUrl,
    String? previewUrl,
    int? previewWidth,
    int? previewHeight,
    String? hlsUrl,
    String? fallbackVideoUrl,
    @Default(<GalleryImage>[]) List<GalleryImage> gallery,
    // vote state: true=up, false=down, null=none
    bool? likes,
  }) = _Post;

  /// Parses a single listing child's `data` object.
  factory Post.fromData(Map<String, dynamic> d) {
    final preview = _firstPreviewImage(d);
    final isVideo = d['is_video'] == true;
    final media = d['media'] as Map<String, dynamic>?;
    final redditVideo = media?['reddit_video'] as Map<String, dynamic>?;
    final gallery = _parseGallery(d);

    return Post(
      id: d['id'] as String? ?? '',
      fullname: d['name'] as String? ?? 't3_${d['id']}',
      title: (d['title'] as String? ?? '').trim(),
      subreddit: d['subreddit'] as String? ?? '',
      subredditPrefixed: d['subreddit_name_prefixed'] as String? ?? '',
      author: d['author'] as String? ?? '[deleted]',
      score: (d['score'] as num?)?.toInt() ?? 0,
      numComments: (d['num_comments'] as num?)?.toInt() ?? 0,
      upvoteRatio: (d['upvote_ratio'] as num?)?.toDouble() ?? 0,
      created: DateTime.fromMillisecondsSinceEpoch(
        ((d['created_utc'] as num?)?.toInt() ?? 0) * 1000,
        isUtc: true,
      ),
      permalink: d['permalink'] as String? ?? '',
      url: d['url'] as String? ?? '',
      domain: d['domain'] as String? ?? '',
      type: _detectType(d, isVideo, gallery.isNotEmpty),
      isSelf: d['is_self'] == true,
      selftext: d['selftext'] as String? ?? '',
      over18: d['over_18'] == true,
      spoiler: d['spoiler'] == true,
      stickied: d['stickied'] == true,
      locked: d['locked'] == true,
      saved: d['saved'] == true,
      canModPost: d['can_mod_post'] == true,
      linkFlairText: (d['link_flair_text'] as String?)?.trim().isEmpty ?? true
          ? null
          : d['link_flair_text'] as String?,
      distinguished: d['distinguished'] as String?,
      crosspostFrom: _crosspostFrom(d),
      pollOptions: _pollOptions(d),
      thumbnailUrl: _validThumb(d['thumbnail'] as String?),
      previewUrl: preview?.url,
      previewWidth: preview?.width,
      previewHeight: preview?.height,
      hlsUrl: redditVideo?['hls_url'] as String?,
      fallbackVideoUrl: redditVideo?['fallback_url'] as String?,
      gallery: gallery,
      likes: d['likes'] as bool?,
    );
  }

  bool get hasMedia =>
      previewUrl != null || gallery.isNotEmpty || type == PostType.video;
}

String? _crosspostFrom(Map<String, dynamic> d) {
  final list = d['crosspost_parent_list'] as List?;
  if (list == null || list.isEmpty) return null;
  return (list.first as Map)['subreddit'] as String?;
}

List<String> _pollOptions(Map<String, dynamic> d) {
  final poll = d['poll_data'] as Map<String, dynamic>?;
  final opts = poll?['options'] as List?;
  if (opts == null) return const [];
  return [
    for (final o in opts) (o as Map)['text'] as String? ?? '',
  ]..removeWhere((e) => e.isEmpty);
}

PostType _detectType(Map<String, dynamic> d, bool isVideo, bool hasGallery) {
  if (d['is_self'] == true) return PostType.self;
  if (hasGallery) return PostType.gallery;
  if (isVideo) return PostType.video;
  final hint = d['post_hint'] as String?;
  if (hint == 'image') return PostType.image;
  if (hint == 'rich:video' || hint == 'hosted:video') return PostType.video;
  final url = (d['url'] as String? ?? '').toLowerCase();
  if (url.endsWith('.gif')) return PostType.gif;
  if (url.endsWith('.jpg') || url.endsWith('.jpeg') || url.endsWith('.png') ||
      url.endsWith('.webp')) {
    return PostType.image;
  }
  if (url.endsWith('.gifv') || url.endsWith('.mp4')) return PostType.video;
  return PostType.link;
}

String? _validThumb(String? thumb) {
  if (thumb == null) return null;
  if (thumb == 'self' || thumb == 'default' || thumb == 'nsfw' ||
      thumb == 'spoiler' || thumb == 'image' || thumb.isEmpty) {
    return null;
  }
  return thumb;
}

({String url, int? width, int? height})? _firstPreviewImage(
    Map<String, dynamic> d) {
  final preview = d['preview'] as Map<String, dynamic>?;
  final images = preview?['images'] as List?;
  if (images == null || images.isEmpty) return null;
  final source = (images.first as Map)['source'] as Map<String, dynamic>?;
  final src = source?['url'] as String?;
  if (src == null) return null;
  return (
    url: src,
    width: (source?['width'] as num?)?.toInt(),
    height: (source?['height'] as num?)?.toInt(),
  );
}

List<GalleryImage> _parseGallery(Map<String, dynamic> d) {
  final galleryData = d['gallery_data'] as Map<String, dynamic>?;
  final metadata = d['media_metadata'] as Map<String, dynamic>?;
  if (galleryData == null || metadata == null) return const [];
  final items = galleryData['items'] as List? ?? [];
  final result = <GalleryImage>[];
  for (final item in items) {
    final mediaId = (item as Map)['media_id'] as String?;
    if (mediaId == null) continue;
    final meta = metadata[mediaId] as Map<String, dynamic>?;
    final s = meta?['s'] as Map<String, dynamic>?;
    final url = (s?['u'] ?? s?['gif']) as String?;
    if (url == null) continue;
    result.add(GalleryImage(
      url: url,
      width: (s?['x'] as num?)?.toInt(),
      height: (s?['y'] as num?)?.toInt(),
    ));
  }
  return result;
}
