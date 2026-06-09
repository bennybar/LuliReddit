// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'comment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Comment {
  String get id => throw _privateConstructorUsedError;
  String get fullname => throw _privateConstructorUsedError; // t1_xxx
  String get parentId => throw _privateConstructorUsedError; // t1_xxx or t3_xxx
  String get author => throw _privateConstructorUsedError;
  String get body => throw _privateConstructorUsedError;
  int get score => throw _privateConstructorUsedError;
  DateTime get created => throw _privateConstructorUsedError;
  int get depth => throw _privateConstructorUsedError;
  String? get distinguished => throw _privateConstructorUsedError;
  bool get stickied => throw _privateConstructorUsedError;
  bool get scoreHidden => throw _privateConstructorUsedError;
  bool get saved => throw _privateConstructorUsedError;
  bool? get likes =>
      throw _privateConstructorUsedError; // Present on user/saved comment listings — link back to the parent post.
  String get linkTitle => throw _privateConstructorUsedError;
  String get permalink => throw _privateConstructorUsedError;
  String get subreddit => throw _privateConstructorUsedError;
  List<Comment> get replies =>
      throw _privateConstructorUsedError; // "more" placeholder fields
  bool get isMore => throw _privateConstructorUsedError;
  int get moreCount => throw _privateConstructorUsedError;
  List<String> get moreChildren => throw _privateConstructorUsedError;
  bool get collapsed => throw _privateConstructorUsedError;

  /// Create a copy of Comment
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CommentCopyWith<Comment> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CommentCopyWith<$Res> {
  factory $CommentCopyWith(Comment value, $Res Function(Comment) then) =
      _$CommentCopyWithImpl<$Res, Comment>;
  @useResult
  $Res call({
    String id,
    String fullname,
    String parentId,
    String author,
    String body,
    int score,
    DateTime created,
    int depth,
    String? distinguished,
    bool stickied,
    bool scoreHidden,
    bool saved,
    bool? likes,
    String linkTitle,
    String permalink,
    String subreddit,
    List<Comment> replies,
    bool isMore,
    int moreCount,
    List<String> moreChildren,
    bool collapsed,
  });
}

/// @nodoc
class _$CommentCopyWithImpl<$Res, $Val extends Comment>
    implements $CommentCopyWith<$Res> {
  _$CommentCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Comment
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? fullname = null,
    Object? parentId = null,
    Object? author = null,
    Object? body = null,
    Object? score = null,
    Object? created = null,
    Object? depth = null,
    Object? distinguished = freezed,
    Object? stickied = null,
    Object? scoreHidden = null,
    Object? saved = null,
    Object? likes = freezed,
    Object? linkTitle = null,
    Object? permalink = null,
    Object? subreddit = null,
    Object? replies = null,
    Object? isMore = null,
    Object? moreCount = null,
    Object? moreChildren = null,
    Object? collapsed = null,
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
            parentId: null == parentId
                ? _value.parentId
                : parentId // ignore: cast_nullable_to_non_nullable
                      as String,
            author: null == author
                ? _value.author
                : author // ignore: cast_nullable_to_non_nullable
                      as String,
            body: null == body
                ? _value.body
                : body // ignore: cast_nullable_to_non_nullable
                      as String,
            score: null == score
                ? _value.score
                : score // ignore: cast_nullable_to_non_nullable
                      as int,
            created: null == created
                ? _value.created
                : created // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            depth: null == depth
                ? _value.depth
                : depth // ignore: cast_nullable_to_non_nullable
                      as int,
            distinguished: freezed == distinguished
                ? _value.distinguished
                : distinguished // ignore: cast_nullable_to_non_nullable
                      as String?,
            stickied: null == stickied
                ? _value.stickied
                : stickied // ignore: cast_nullable_to_non_nullable
                      as bool,
            scoreHidden: null == scoreHidden
                ? _value.scoreHidden
                : scoreHidden // ignore: cast_nullable_to_non_nullable
                      as bool,
            saved: null == saved
                ? _value.saved
                : saved // ignore: cast_nullable_to_non_nullable
                      as bool,
            likes: freezed == likes
                ? _value.likes
                : likes // ignore: cast_nullable_to_non_nullable
                      as bool?,
            linkTitle: null == linkTitle
                ? _value.linkTitle
                : linkTitle // ignore: cast_nullable_to_non_nullable
                      as String,
            permalink: null == permalink
                ? _value.permalink
                : permalink // ignore: cast_nullable_to_non_nullable
                      as String,
            subreddit: null == subreddit
                ? _value.subreddit
                : subreddit // ignore: cast_nullable_to_non_nullable
                      as String,
            replies: null == replies
                ? _value.replies
                : replies // ignore: cast_nullable_to_non_nullable
                      as List<Comment>,
            isMore: null == isMore
                ? _value.isMore
                : isMore // ignore: cast_nullable_to_non_nullable
                      as bool,
            moreCount: null == moreCount
                ? _value.moreCount
                : moreCount // ignore: cast_nullable_to_non_nullable
                      as int,
            moreChildren: null == moreChildren
                ? _value.moreChildren
                : moreChildren // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            collapsed: null == collapsed
                ? _value.collapsed
                : collapsed // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$CommentImplCopyWith<$Res> implements $CommentCopyWith<$Res> {
  factory _$$CommentImplCopyWith(
    _$CommentImpl value,
    $Res Function(_$CommentImpl) then,
  ) = __$$CommentImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String fullname,
    String parentId,
    String author,
    String body,
    int score,
    DateTime created,
    int depth,
    String? distinguished,
    bool stickied,
    bool scoreHidden,
    bool saved,
    bool? likes,
    String linkTitle,
    String permalink,
    String subreddit,
    List<Comment> replies,
    bool isMore,
    int moreCount,
    List<String> moreChildren,
    bool collapsed,
  });
}

/// @nodoc
class __$$CommentImplCopyWithImpl<$Res>
    extends _$CommentCopyWithImpl<$Res, _$CommentImpl>
    implements _$$CommentImplCopyWith<$Res> {
  __$$CommentImplCopyWithImpl(
    _$CommentImpl _value,
    $Res Function(_$CommentImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Comment
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? fullname = null,
    Object? parentId = null,
    Object? author = null,
    Object? body = null,
    Object? score = null,
    Object? created = null,
    Object? depth = null,
    Object? distinguished = freezed,
    Object? stickied = null,
    Object? scoreHidden = null,
    Object? saved = null,
    Object? likes = freezed,
    Object? linkTitle = null,
    Object? permalink = null,
    Object? subreddit = null,
    Object? replies = null,
    Object? isMore = null,
    Object? moreCount = null,
    Object? moreChildren = null,
    Object? collapsed = null,
  }) {
    return _then(
      _$CommentImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        fullname: null == fullname
            ? _value.fullname
            : fullname // ignore: cast_nullable_to_non_nullable
                  as String,
        parentId: null == parentId
            ? _value.parentId
            : parentId // ignore: cast_nullable_to_non_nullable
                  as String,
        author: null == author
            ? _value.author
            : author // ignore: cast_nullable_to_non_nullable
                  as String,
        body: null == body
            ? _value.body
            : body // ignore: cast_nullable_to_non_nullable
                  as String,
        score: null == score
            ? _value.score
            : score // ignore: cast_nullable_to_non_nullable
                  as int,
        created: null == created
            ? _value.created
            : created // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        depth: null == depth
            ? _value.depth
            : depth // ignore: cast_nullable_to_non_nullable
                  as int,
        distinguished: freezed == distinguished
            ? _value.distinguished
            : distinguished // ignore: cast_nullable_to_non_nullable
                  as String?,
        stickied: null == stickied
            ? _value.stickied
            : stickied // ignore: cast_nullable_to_non_nullable
                  as bool,
        scoreHidden: null == scoreHidden
            ? _value.scoreHidden
            : scoreHidden // ignore: cast_nullable_to_non_nullable
                  as bool,
        saved: null == saved
            ? _value.saved
            : saved // ignore: cast_nullable_to_non_nullable
                  as bool,
        likes: freezed == likes
            ? _value.likes
            : likes // ignore: cast_nullable_to_non_nullable
                  as bool?,
        linkTitle: null == linkTitle
            ? _value.linkTitle
            : linkTitle // ignore: cast_nullable_to_non_nullable
                  as String,
        permalink: null == permalink
            ? _value.permalink
            : permalink // ignore: cast_nullable_to_non_nullable
                  as String,
        subreddit: null == subreddit
            ? _value.subreddit
            : subreddit // ignore: cast_nullable_to_non_nullable
                  as String,
        replies: null == replies
            ? _value._replies
            : replies // ignore: cast_nullable_to_non_nullable
                  as List<Comment>,
        isMore: null == isMore
            ? _value.isMore
            : isMore // ignore: cast_nullable_to_non_nullable
                  as bool,
        moreCount: null == moreCount
            ? _value.moreCount
            : moreCount // ignore: cast_nullable_to_non_nullable
                  as int,
        moreChildren: null == moreChildren
            ? _value._moreChildren
            : moreChildren // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        collapsed: null == collapsed
            ? _value.collapsed
            : collapsed // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc

class _$CommentImpl extends _Comment {
  const _$CommentImpl({
    required this.id,
    required this.fullname,
    this.parentId = '',
    required this.author,
    required this.body,
    required this.score,
    required this.created,
    required this.depth,
    this.distinguished,
    this.stickied = false,
    this.scoreHidden = false,
    this.saved = false,
    this.likes,
    this.linkTitle = '',
    this.permalink = '',
    this.subreddit = '',
    final List<Comment> replies = const <Comment>[],
    this.isMore = false,
    this.moreCount = 0,
    final List<String> moreChildren = const <String>[],
    this.collapsed = false,
  }) : _replies = replies,
       _moreChildren = moreChildren,
       super._();

  @override
  final String id;
  @override
  final String fullname;
  // t1_xxx
  @override
  @JsonKey()
  final String parentId;
  // t1_xxx or t3_xxx
  @override
  final String author;
  @override
  final String body;
  @override
  final int score;
  @override
  final DateTime created;
  @override
  final int depth;
  @override
  final String? distinguished;
  @override
  @JsonKey()
  final bool stickied;
  @override
  @JsonKey()
  final bool scoreHidden;
  @override
  @JsonKey()
  final bool saved;
  @override
  final bool? likes;
  // Present on user/saved comment listings — link back to the parent post.
  @override
  @JsonKey()
  final String linkTitle;
  @override
  @JsonKey()
  final String permalink;
  @override
  @JsonKey()
  final String subreddit;
  final List<Comment> _replies;
  @override
  @JsonKey()
  List<Comment> get replies {
    if (_replies is EqualUnmodifiableListView) return _replies;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_replies);
  }

  // "more" placeholder fields
  @override
  @JsonKey()
  final bool isMore;
  @override
  @JsonKey()
  final int moreCount;
  final List<String> _moreChildren;
  @override
  @JsonKey()
  List<String> get moreChildren {
    if (_moreChildren is EqualUnmodifiableListView) return _moreChildren;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_moreChildren);
  }

  @override
  @JsonKey()
  final bool collapsed;

  @override
  String toString() {
    return 'Comment(id: $id, fullname: $fullname, parentId: $parentId, author: $author, body: $body, score: $score, created: $created, depth: $depth, distinguished: $distinguished, stickied: $stickied, scoreHidden: $scoreHidden, saved: $saved, likes: $likes, linkTitle: $linkTitle, permalink: $permalink, subreddit: $subreddit, replies: $replies, isMore: $isMore, moreCount: $moreCount, moreChildren: $moreChildren, collapsed: $collapsed)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CommentImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.fullname, fullname) ||
                other.fullname == fullname) &&
            (identical(other.parentId, parentId) ||
                other.parentId == parentId) &&
            (identical(other.author, author) || other.author == author) &&
            (identical(other.body, body) || other.body == body) &&
            (identical(other.score, score) || other.score == score) &&
            (identical(other.created, created) || other.created == created) &&
            (identical(other.depth, depth) || other.depth == depth) &&
            (identical(other.distinguished, distinguished) ||
                other.distinguished == distinguished) &&
            (identical(other.stickied, stickied) ||
                other.stickied == stickied) &&
            (identical(other.scoreHidden, scoreHidden) ||
                other.scoreHidden == scoreHidden) &&
            (identical(other.saved, saved) || other.saved == saved) &&
            (identical(other.likes, likes) || other.likes == likes) &&
            (identical(other.linkTitle, linkTitle) ||
                other.linkTitle == linkTitle) &&
            (identical(other.permalink, permalink) ||
                other.permalink == permalink) &&
            (identical(other.subreddit, subreddit) ||
                other.subreddit == subreddit) &&
            const DeepCollectionEquality().equals(other._replies, _replies) &&
            (identical(other.isMore, isMore) || other.isMore == isMore) &&
            (identical(other.moreCount, moreCount) ||
                other.moreCount == moreCount) &&
            const DeepCollectionEquality().equals(
              other._moreChildren,
              _moreChildren,
            ) &&
            (identical(other.collapsed, collapsed) ||
                other.collapsed == collapsed));
  }

  @override
  int get hashCode => Object.hashAll([
    runtimeType,
    id,
    fullname,
    parentId,
    author,
    body,
    score,
    created,
    depth,
    distinguished,
    stickied,
    scoreHidden,
    saved,
    likes,
    linkTitle,
    permalink,
    subreddit,
    const DeepCollectionEquality().hash(_replies),
    isMore,
    moreCount,
    const DeepCollectionEquality().hash(_moreChildren),
    collapsed,
  ]);

  /// Create a copy of Comment
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CommentImplCopyWith<_$CommentImpl> get copyWith =>
      __$$CommentImplCopyWithImpl<_$CommentImpl>(this, _$identity);
}

abstract class _Comment extends Comment {
  const factory _Comment({
    required final String id,
    required final String fullname,
    final String parentId,
    required final String author,
    required final String body,
    required final int score,
    required final DateTime created,
    required final int depth,
    final String? distinguished,
    final bool stickied,
    final bool scoreHidden,
    final bool saved,
    final bool? likes,
    final String linkTitle,
    final String permalink,
    final String subreddit,
    final List<Comment> replies,
    final bool isMore,
    final int moreCount,
    final List<String> moreChildren,
    final bool collapsed,
  }) = _$CommentImpl;
  const _Comment._() : super._();

  @override
  String get id;
  @override
  String get fullname; // t1_xxx
  @override
  String get parentId; // t1_xxx or t3_xxx
  @override
  String get author;
  @override
  String get body;
  @override
  int get score;
  @override
  DateTime get created;
  @override
  int get depth;
  @override
  String? get distinguished;
  @override
  bool get stickied;
  @override
  bool get scoreHidden;
  @override
  bool get saved;
  @override
  bool? get likes; // Present on user/saved comment listings — link back to the parent post.
  @override
  String get linkTitle;
  @override
  String get permalink;
  @override
  String get subreddit;
  @override
  List<Comment> get replies; // "more" placeholder fields
  @override
  bool get isMore;
  @override
  int get moreCount;
  @override
  List<String> get moreChildren;
  @override
  bool get collapsed;

  /// Create a copy of Comment
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CommentImplCopyWith<_$CommentImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
