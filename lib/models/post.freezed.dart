// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'post.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Post {
  String get id => throw _privateConstructorUsedError;
  String get fullname => throw _privateConstructorUsedError; // t3_xxx
  String get title => throw _privateConstructorUsedError;
  String get subreddit => throw _privateConstructorUsedError;
  String get subredditPrefixed => throw _privateConstructorUsedError;
  String get author => throw _privateConstructorUsedError;
  int get score => throw _privateConstructorUsedError;
  int get numComments => throw _privateConstructorUsedError;
  double get upvoteRatio => throw _privateConstructorUsedError;
  DateTime get created => throw _privateConstructorUsedError;
  String get permalink => throw _privateConstructorUsedError;
  String get url => throw _privateConstructorUsedError;
  String get domain => throw _privateConstructorUsedError;
  PostType get type => throw _privateConstructorUsedError;
  bool get isSelf => throw _privateConstructorUsedError;
  String get selftext => throw _privateConstructorUsedError;
  bool get over18 => throw _privateConstructorUsedError;
  bool get spoiler => throw _privateConstructorUsedError;
  bool get stickied => throw _privateConstructorUsedError;
  bool get locked => throw _privateConstructorUsedError;
  bool get saved => throw _privateConstructorUsedError;
  bool get canModPost => throw _privateConstructorUsedError;
  String? get linkFlairText => throw _privateConstructorUsedError;
  String? get distinguished => throw _privateConstructorUsedError;
  String? get feedReason =>
      throw _privateConstructorUsedError; // "why you're seeing this" in the For You feed (transient)
  String? get crosspostFrom =>
      throw _privateConstructorUsedError; // subreddit a crosspost originates from
  List<String> get pollOptions => throw _privateConstructorUsedError; // media
  String? get thumbnailUrl => throw _privateConstructorUsedError;
  String? get previewUrl => throw _privateConstructorUsedError;
  String? get previewMedUrl =>
      throw _privateConstructorUsedError; // smaller resolution for feed cards
  int? get previewWidth => throw _privateConstructorUsedError;
  int? get previewHeight => throw _privateConstructorUsedError;
  String? get hlsUrl => throw _privateConstructorUsedError;
  String? get fallbackVideoUrl => throw _privateConstructorUsedError;
  String? get gifMp4Url =>
      throw _privateConstructorUsedError; // reddit's mp4 variant for GIF posts (much smaller)
  List<GalleryImage> get gallery =>
      throw _privateConstructorUsedError; // vote state: true=up, false=down, null=none
  bool? get likes => throw _privateConstructorUsedError;

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PostCopyWith<Post> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PostCopyWith<$Res> {
  factory $PostCopyWith(Post value, $Res Function(Post) then) =
      _$PostCopyWithImpl<$Res, Post>;
  @useResult
  $Res call({
    String id,
    String fullname,
    String title,
    String subreddit,
    String subredditPrefixed,
    String author,
    int score,
    int numComments,
    double upvoteRatio,
    DateTime created,
    String permalink,
    String url,
    String domain,
    PostType type,
    bool isSelf,
    String selftext,
    bool over18,
    bool spoiler,
    bool stickied,
    bool locked,
    bool saved,
    bool canModPost,
    String? linkFlairText,
    String? distinguished,
    String? feedReason,
    String? crosspostFrom,
    List<String> pollOptions,
    String? thumbnailUrl,
    String? previewUrl,
    String? previewMedUrl,
    int? previewWidth,
    int? previewHeight,
    String? hlsUrl,
    String? fallbackVideoUrl,
    String? gifMp4Url,
    List<GalleryImage> gallery,
    bool? likes,
  });
}

/// @nodoc
class _$PostCopyWithImpl<$Res, $Val extends Post>
    implements $PostCopyWith<$Res> {
  _$PostCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? fullname = null,
    Object? title = null,
    Object? subreddit = null,
    Object? subredditPrefixed = null,
    Object? author = null,
    Object? score = null,
    Object? numComments = null,
    Object? upvoteRatio = null,
    Object? created = null,
    Object? permalink = null,
    Object? url = null,
    Object? domain = null,
    Object? type = null,
    Object? isSelf = null,
    Object? selftext = null,
    Object? over18 = null,
    Object? spoiler = null,
    Object? stickied = null,
    Object? locked = null,
    Object? saved = null,
    Object? canModPost = null,
    Object? linkFlairText = freezed,
    Object? distinguished = freezed,
    Object? feedReason = freezed,
    Object? crosspostFrom = freezed,
    Object? pollOptions = null,
    Object? thumbnailUrl = freezed,
    Object? previewUrl = freezed,
    Object? previewMedUrl = freezed,
    Object? previewWidth = freezed,
    Object? previewHeight = freezed,
    Object? hlsUrl = freezed,
    Object? fallbackVideoUrl = freezed,
    Object? gifMp4Url = freezed,
    Object? gallery = null,
    Object? likes = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            fullname: null == fullname
                ? _value.fullname
                : fullname // ignore: cast_nullable_to_non_nullable
                      as String,
            title: null == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String,
            subreddit: null == subreddit
                ? _value.subreddit
                : subreddit // ignore: cast_nullable_to_non_nullable
                      as String,
            subredditPrefixed: null == subredditPrefixed
                ? _value.subredditPrefixed
                : subredditPrefixed // ignore: cast_nullable_to_non_nullable
                      as String,
            author: null == author
                ? _value.author
                : author // ignore: cast_nullable_to_non_nullable
                      as String,
            score: null == score
                ? _value.score
                : score // ignore: cast_nullable_to_non_nullable
                      as int,
            numComments: null == numComments
                ? _value.numComments
                : numComments // ignore: cast_nullable_to_non_nullable
                      as int,
            upvoteRatio: null == upvoteRatio
                ? _value.upvoteRatio
                : upvoteRatio // ignore: cast_nullable_to_non_nullable
                      as double,
            created: null == created
                ? _value.created
                : created // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            permalink: null == permalink
                ? _value.permalink
                : permalink // ignore: cast_nullable_to_non_nullable
                      as String,
            url: null == url
                ? _value.url
                : url // ignore: cast_nullable_to_non_nullable
                      as String,
            domain: null == domain
                ? _value.domain
                : domain // ignore: cast_nullable_to_non_nullable
                      as String,
            type: null == type
                ? _value.type
                : type // ignore: cast_nullable_to_non_nullable
                      as PostType,
            isSelf: null == isSelf
                ? _value.isSelf
                : isSelf // ignore: cast_nullable_to_non_nullable
                      as bool,
            selftext: null == selftext
                ? _value.selftext
                : selftext // ignore: cast_nullable_to_non_nullable
                      as String,
            over18: null == over18
                ? _value.over18
                : over18 // ignore: cast_nullable_to_non_nullable
                      as bool,
            spoiler: null == spoiler
                ? _value.spoiler
                : spoiler // ignore: cast_nullable_to_non_nullable
                      as bool,
            stickied: null == stickied
                ? _value.stickied
                : stickied // ignore: cast_nullable_to_non_nullable
                      as bool,
            locked: null == locked
                ? _value.locked
                : locked // ignore: cast_nullable_to_non_nullable
                      as bool,
            saved: null == saved
                ? _value.saved
                : saved // ignore: cast_nullable_to_non_nullable
                      as bool,
            canModPost: null == canModPost
                ? _value.canModPost
                : canModPost // ignore: cast_nullable_to_non_nullable
                      as bool,
            linkFlairText: freezed == linkFlairText
                ? _value.linkFlairText
                : linkFlairText // ignore: cast_nullable_to_non_nullable
                      as String?,
            distinguished: freezed == distinguished
                ? _value.distinguished
                : distinguished // ignore: cast_nullable_to_non_nullable
                      as String?,
            feedReason: freezed == feedReason
                ? _value.feedReason
                : feedReason // ignore: cast_nullable_to_non_nullable
                      as String?,
            crosspostFrom: freezed == crosspostFrom
                ? _value.crosspostFrom
                : crosspostFrom // ignore: cast_nullable_to_non_nullable
                      as String?,
            pollOptions: null == pollOptions
                ? _value.pollOptions
                : pollOptions // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            thumbnailUrl: freezed == thumbnailUrl
                ? _value.thumbnailUrl
                : thumbnailUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            previewUrl: freezed == previewUrl
                ? _value.previewUrl
                : previewUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            previewMedUrl: freezed == previewMedUrl
                ? _value.previewMedUrl
                : previewMedUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            previewWidth: freezed == previewWidth
                ? _value.previewWidth
                : previewWidth // ignore: cast_nullable_to_non_nullable
                      as int?,
            previewHeight: freezed == previewHeight
                ? _value.previewHeight
                : previewHeight // ignore: cast_nullable_to_non_nullable
                      as int?,
            hlsUrl: freezed == hlsUrl
                ? _value.hlsUrl
                : hlsUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            fallbackVideoUrl: freezed == fallbackVideoUrl
                ? _value.fallbackVideoUrl
                : fallbackVideoUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            gifMp4Url: freezed == gifMp4Url
                ? _value.gifMp4Url
                : gifMp4Url // ignore: cast_nullable_to_non_nullable
                      as String?,
            gallery: null == gallery
                ? _value.gallery
                : gallery // ignore: cast_nullable_to_non_nullable
                      as List<GalleryImage>,
            likes: freezed == likes
                ? _value.likes
                : likes // ignore: cast_nullable_to_non_nullable
                      as bool?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$PostImplCopyWith<$Res> implements $PostCopyWith<$Res> {
  factory _$$PostImplCopyWith(
    _$PostImpl value,
    $Res Function(_$PostImpl) then,
  ) = __$$PostImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String fullname,
    String title,
    String subreddit,
    String subredditPrefixed,
    String author,
    int score,
    int numComments,
    double upvoteRatio,
    DateTime created,
    String permalink,
    String url,
    String domain,
    PostType type,
    bool isSelf,
    String selftext,
    bool over18,
    bool spoiler,
    bool stickied,
    bool locked,
    bool saved,
    bool canModPost,
    String? linkFlairText,
    String? distinguished,
    String? feedReason,
    String? crosspostFrom,
    List<String> pollOptions,
    String? thumbnailUrl,
    String? previewUrl,
    String? previewMedUrl,
    int? previewWidth,
    int? previewHeight,
    String? hlsUrl,
    String? fallbackVideoUrl,
    String? gifMp4Url,
    List<GalleryImage> gallery,
    bool? likes,
  });
}

/// @nodoc
class __$$PostImplCopyWithImpl<$Res>
    extends _$PostCopyWithImpl<$Res, _$PostImpl>
    implements _$$PostImplCopyWith<$Res> {
  __$$PostImplCopyWithImpl(_$PostImpl _value, $Res Function(_$PostImpl) _then)
    : super(_value, _then);

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? fullname = null,
    Object? title = null,
    Object? subreddit = null,
    Object? subredditPrefixed = null,
    Object? author = null,
    Object? score = null,
    Object? numComments = null,
    Object? upvoteRatio = null,
    Object? created = null,
    Object? permalink = null,
    Object? url = null,
    Object? domain = null,
    Object? type = null,
    Object? isSelf = null,
    Object? selftext = null,
    Object? over18 = null,
    Object? spoiler = null,
    Object? stickied = null,
    Object? locked = null,
    Object? saved = null,
    Object? canModPost = null,
    Object? linkFlairText = freezed,
    Object? distinguished = freezed,
    Object? feedReason = freezed,
    Object? crosspostFrom = freezed,
    Object? pollOptions = null,
    Object? thumbnailUrl = freezed,
    Object? previewUrl = freezed,
    Object? previewMedUrl = freezed,
    Object? previewWidth = freezed,
    Object? previewHeight = freezed,
    Object? hlsUrl = freezed,
    Object? fallbackVideoUrl = freezed,
    Object? gifMp4Url = freezed,
    Object? gallery = null,
    Object? likes = freezed,
  }) {
    return _then(
      _$PostImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        fullname: null == fullname
            ? _value.fullname
            : fullname // ignore: cast_nullable_to_non_nullable
                  as String,
        title: null == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String,
        subreddit: null == subreddit
            ? _value.subreddit
            : subreddit // ignore: cast_nullable_to_non_nullable
                  as String,
        subredditPrefixed: null == subredditPrefixed
            ? _value.subredditPrefixed
            : subredditPrefixed // ignore: cast_nullable_to_non_nullable
                  as String,
        author: null == author
            ? _value.author
            : author // ignore: cast_nullable_to_non_nullable
                  as String,
        score: null == score
            ? _value.score
            : score // ignore: cast_nullable_to_non_nullable
                  as int,
        numComments: null == numComments
            ? _value.numComments
            : numComments // ignore: cast_nullable_to_non_nullable
                  as int,
        upvoteRatio: null == upvoteRatio
            ? _value.upvoteRatio
            : upvoteRatio // ignore: cast_nullable_to_non_nullable
                  as double,
        created: null == created
            ? _value.created
            : created // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        permalink: null == permalink
            ? _value.permalink
            : permalink // ignore: cast_nullable_to_non_nullable
                  as String,
        url: null == url
            ? _value.url
            : url // ignore: cast_nullable_to_non_nullable
                  as String,
        domain: null == domain
            ? _value.domain
            : domain // ignore: cast_nullable_to_non_nullable
                  as String,
        type: null == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as PostType,
        isSelf: null == isSelf
            ? _value.isSelf
            : isSelf // ignore: cast_nullable_to_non_nullable
                  as bool,
        selftext: null == selftext
            ? _value.selftext
            : selftext // ignore: cast_nullable_to_non_nullable
                  as String,
        over18: null == over18
            ? _value.over18
            : over18 // ignore: cast_nullable_to_non_nullable
                  as bool,
        spoiler: null == spoiler
            ? _value.spoiler
            : spoiler // ignore: cast_nullable_to_non_nullable
                  as bool,
        stickied: null == stickied
            ? _value.stickied
            : stickied // ignore: cast_nullable_to_non_nullable
                  as bool,
        locked: null == locked
            ? _value.locked
            : locked // ignore: cast_nullable_to_non_nullable
                  as bool,
        saved: null == saved
            ? _value.saved
            : saved // ignore: cast_nullable_to_non_nullable
                  as bool,
        canModPost: null == canModPost
            ? _value.canModPost
            : canModPost // ignore: cast_nullable_to_non_nullable
                  as bool,
        linkFlairText: freezed == linkFlairText
            ? _value.linkFlairText
            : linkFlairText // ignore: cast_nullable_to_non_nullable
                  as String?,
        distinguished: freezed == distinguished
            ? _value.distinguished
            : distinguished // ignore: cast_nullable_to_non_nullable
                  as String?,
        feedReason: freezed == feedReason
            ? _value.feedReason
            : feedReason // ignore: cast_nullable_to_non_nullable
                  as String?,
        crosspostFrom: freezed == crosspostFrom
            ? _value.crosspostFrom
            : crosspostFrom // ignore: cast_nullable_to_non_nullable
                  as String?,
        pollOptions: null == pollOptions
            ? _value._pollOptions
            : pollOptions // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        thumbnailUrl: freezed == thumbnailUrl
            ? _value.thumbnailUrl
            : thumbnailUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        previewUrl: freezed == previewUrl
            ? _value.previewUrl
            : previewUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        previewMedUrl: freezed == previewMedUrl
            ? _value.previewMedUrl
            : previewMedUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        previewWidth: freezed == previewWidth
            ? _value.previewWidth
            : previewWidth // ignore: cast_nullable_to_non_nullable
                  as int?,
        previewHeight: freezed == previewHeight
            ? _value.previewHeight
            : previewHeight // ignore: cast_nullable_to_non_nullable
                  as int?,
        hlsUrl: freezed == hlsUrl
            ? _value.hlsUrl
            : hlsUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        fallbackVideoUrl: freezed == fallbackVideoUrl
            ? _value.fallbackVideoUrl
            : fallbackVideoUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        gifMp4Url: freezed == gifMp4Url
            ? _value.gifMp4Url
            : gifMp4Url // ignore: cast_nullable_to_non_nullable
                  as String?,
        gallery: null == gallery
            ? _value._gallery
            : gallery // ignore: cast_nullable_to_non_nullable
                  as List<GalleryImage>,
        likes: freezed == likes
            ? _value.likes
            : likes // ignore: cast_nullable_to_non_nullable
                  as bool?,
      ),
    );
  }
}

/// @nodoc

class _$PostImpl extends _Post {
  const _$PostImpl({
    required this.id,
    required this.fullname,
    required this.title,
    required this.subreddit,
    required this.subredditPrefixed,
    required this.author,
    required this.score,
    required this.numComments,
    required this.upvoteRatio,
    required this.created,
    required this.permalink,
    required this.url,
    required this.domain,
    required this.type,
    this.isSelf = false,
    this.selftext = '',
    this.over18 = false,
    this.spoiler = false,
    this.stickied = false,
    this.locked = false,
    this.saved = false,
    this.canModPost = false,
    this.linkFlairText,
    this.distinguished,
    this.feedReason,
    this.crosspostFrom,
    final List<String> pollOptions = const <String>[],
    this.thumbnailUrl,
    this.previewUrl,
    this.previewMedUrl,
    this.previewWidth,
    this.previewHeight,
    this.hlsUrl,
    this.fallbackVideoUrl,
    this.gifMp4Url,
    final List<GalleryImage> gallery = const <GalleryImage>[],
    this.likes,
  }) : _pollOptions = pollOptions,
       _gallery = gallery,
       super._();

  @override
  final String id;
  @override
  final String fullname;
  // t3_xxx
  @override
  final String title;
  @override
  final String subreddit;
  @override
  final String subredditPrefixed;
  @override
  final String author;
  @override
  final int score;
  @override
  final int numComments;
  @override
  final double upvoteRatio;
  @override
  final DateTime created;
  @override
  final String permalink;
  @override
  final String url;
  @override
  final String domain;
  @override
  final PostType type;
  @override
  @JsonKey()
  final bool isSelf;
  @override
  @JsonKey()
  final String selftext;
  @override
  @JsonKey()
  final bool over18;
  @override
  @JsonKey()
  final bool spoiler;
  @override
  @JsonKey()
  final bool stickied;
  @override
  @JsonKey()
  final bool locked;
  @override
  @JsonKey()
  final bool saved;
  @override
  @JsonKey()
  final bool canModPost;
  @override
  final String? linkFlairText;
  @override
  final String? distinguished;
  @override
  final String? feedReason;
  // "why you're seeing this" in the For You feed (transient)
  @override
  final String? crosspostFrom;
  // subreddit a crosspost originates from
  final List<String> _pollOptions;
  // subreddit a crosspost originates from
  @override
  @JsonKey()
  List<String> get pollOptions {
    if (_pollOptions is EqualUnmodifiableListView) return _pollOptions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_pollOptions);
  }

  // media
  @override
  final String? thumbnailUrl;
  @override
  final String? previewUrl;
  @override
  final String? previewMedUrl;
  // smaller resolution for feed cards
  @override
  final int? previewWidth;
  @override
  final int? previewHeight;
  @override
  final String? hlsUrl;
  @override
  final String? fallbackVideoUrl;
  @override
  final String? gifMp4Url;
  // reddit's mp4 variant for GIF posts (much smaller)
  final List<GalleryImage> _gallery;
  // reddit's mp4 variant for GIF posts (much smaller)
  @override
  @JsonKey()
  List<GalleryImage> get gallery {
    if (_gallery is EqualUnmodifiableListView) return _gallery;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_gallery);
  }

  // vote state: true=up, false=down, null=none
  @override
  final bool? likes;

  @override
  String toString() {
    return 'Post(id: $id, fullname: $fullname, title: $title, subreddit: $subreddit, subredditPrefixed: $subredditPrefixed, author: $author, score: $score, numComments: $numComments, upvoteRatio: $upvoteRatio, created: $created, permalink: $permalink, url: $url, domain: $domain, type: $type, isSelf: $isSelf, selftext: $selftext, over18: $over18, spoiler: $spoiler, stickied: $stickied, locked: $locked, saved: $saved, canModPost: $canModPost, linkFlairText: $linkFlairText, distinguished: $distinguished, feedReason: $feedReason, crosspostFrom: $crosspostFrom, pollOptions: $pollOptions, thumbnailUrl: $thumbnailUrl, previewUrl: $previewUrl, previewMedUrl: $previewMedUrl, previewWidth: $previewWidth, previewHeight: $previewHeight, hlsUrl: $hlsUrl, fallbackVideoUrl: $fallbackVideoUrl, gifMp4Url: $gifMp4Url, gallery: $gallery, likes: $likes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PostImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.fullname, fullname) ||
                other.fullname == fullname) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.subreddit, subreddit) ||
                other.subreddit == subreddit) &&
            (identical(other.subredditPrefixed, subredditPrefixed) ||
                other.subredditPrefixed == subredditPrefixed) &&
            (identical(other.author, author) || other.author == author) &&
            (identical(other.score, score) || other.score == score) &&
            (identical(other.numComments, numComments) ||
                other.numComments == numComments) &&
            (identical(other.upvoteRatio, upvoteRatio) ||
                other.upvoteRatio == upvoteRatio) &&
            (identical(other.created, created) || other.created == created) &&
            (identical(other.permalink, permalink) ||
                other.permalink == permalink) &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.domain, domain) || other.domain == domain) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.isSelf, isSelf) || other.isSelf == isSelf) &&
            (identical(other.selftext, selftext) ||
                other.selftext == selftext) &&
            (identical(other.over18, over18) || other.over18 == over18) &&
            (identical(other.spoiler, spoiler) || other.spoiler == spoiler) &&
            (identical(other.stickied, stickied) ||
                other.stickied == stickied) &&
            (identical(other.locked, locked) || other.locked == locked) &&
            (identical(other.saved, saved) || other.saved == saved) &&
            (identical(other.canModPost, canModPost) ||
                other.canModPost == canModPost) &&
            (identical(other.linkFlairText, linkFlairText) ||
                other.linkFlairText == linkFlairText) &&
            (identical(other.distinguished, distinguished) ||
                other.distinguished == distinguished) &&
            (identical(other.feedReason, feedReason) ||
                other.feedReason == feedReason) &&
            (identical(other.crosspostFrom, crosspostFrom) ||
                other.crosspostFrom == crosspostFrom) &&
            const DeepCollectionEquality().equals(
              other._pollOptions,
              _pollOptions,
            ) &&
            (identical(other.thumbnailUrl, thumbnailUrl) ||
                other.thumbnailUrl == thumbnailUrl) &&
            (identical(other.previewUrl, previewUrl) ||
                other.previewUrl == previewUrl) &&
            (identical(other.previewMedUrl, previewMedUrl) ||
                other.previewMedUrl == previewMedUrl) &&
            (identical(other.previewWidth, previewWidth) ||
                other.previewWidth == previewWidth) &&
            (identical(other.previewHeight, previewHeight) ||
                other.previewHeight == previewHeight) &&
            (identical(other.hlsUrl, hlsUrl) || other.hlsUrl == hlsUrl) &&
            (identical(other.fallbackVideoUrl, fallbackVideoUrl) ||
                other.fallbackVideoUrl == fallbackVideoUrl) &&
            (identical(other.gifMp4Url, gifMp4Url) ||
                other.gifMp4Url == gifMp4Url) &&
            const DeepCollectionEquality().equals(other._gallery, _gallery) &&
            (identical(other.likes, likes) || other.likes == likes));
  }

  @override
  int get hashCode => Object.hashAll([
    runtimeType,
    id,
    fullname,
    title,
    subreddit,
    subredditPrefixed,
    author,
    score,
    numComments,
    upvoteRatio,
    created,
    permalink,
    url,
    domain,
    type,
    isSelf,
    selftext,
    over18,
    spoiler,
    stickied,
    locked,
    saved,
    canModPost,
    linkFlairText,
    distinguished,
    feedReason,
    crosspostFrom,
    const DeepCollectionEquality().hash(_pollOptions),
    thumbnailUrl,
    previewUrl,
    previewMedUrl,
    previewWidth,
    previewHeight,
    hlsUrl,
    fallbackVideoUrl,
    gifMp4Url,
    const DeepCollectionEquality().hash(_gallery),
    likes,
  ]);

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PostImplCopyWith<_$PostImpl> get copyWith =>
      __$$PostImplCopyWithImpl<_$PostImpl>(this, _$identity);
}

abstract class _Post extends Post {
  const factory _Post({
    required final String id,
    required final String fullname,
    required final String title,
    required final String subreddit,
    required final String subredditPrefixed,
    required final String author,
    required final int score,
    required final int numComments,
    required final double upvoteRatio,
    required final DateTime created,
    required final String permalink,
    required final String url,
    required final String domain,
    required final PostType type,
    final bool isSelf,
    final String selftext,
    final bool over18,
    final bool spoiler,
    final bool stickied,
    final bool locked,
    final bool saved,
    final bool canModPost,
    final String? linkFlairText,
    final String? distinguished,
    final String? feedReason,
    final String? crosspostFrom,
    final List<String> pollOptions,
    final String? thumbnailUrl,
    final String? previewUrl,
    final String? previewMedUrl,
    final int? previewWidth,
    final int? previewHeight,
    final String? hlsUrl,
    final String? fallbackVideoUrl,
    final String? gifMp4Url,
    final List<GalleryImage> gallery,
    final bool? likes,
  }) = _$PostImpl;
  const _Post._() : super._();

  @override
  String get id;
  @override
  String get fullname; // t3_xxx
  @override
  String get title;
  @override
  String get subreddit;
  @override
  String get subredditPrefixed;
  @override
  String get author;
  @override
  int get score;
  @override
  int get numComments;
  @override
  double get upvoteRatio;
  @override
  DateTime get created;
  @override
  String get permalink;
  @override
  String get url;
  @override
  String get domain;
  @override
  PostType get type;
  @override
  bool get isSelf;
  @override
  String get selftext;
  @override
  bool get over18;
  @override
  bool get spoiler;
  @override
  bool get stickied;
  @override
  bool get locked;
  @override
  bool get saved;
  @override
  bool get canModPost;
  @override
  String? get linkFlairText;
  @override
  String? get distinguished;
  @override
  String? get feedReason; // "why you're seeing this" in the For You feed (transient)
  @override
  String? get crosspostFrom; // subreddit a crosspost originates from
  @override
  List<String> get pollOptions; // media
  @override
  String? get thumbnailUrl;
  @override
  String? get previewUrl;
  @override
  String? get previewMedUrl; // smaller resolution for feed cards
  @override
  int? get previewWidth;
  @override
  int? get previewHeight;
  @override
  String? get hlsUrl;
  @override
  String? get fallbackVideoUrl;
  @override
  String? get gifMp4Url; // reddit's mp4 variant for GIF posts (much smaller)
  @override
  List<GalleryImage> get gallery; // vote state: true=up, false=down, null=none
  @override
  bool? get likes;

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PostImplCopyWith<_$PostImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
