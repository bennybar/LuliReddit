// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'inbox_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$InboxItem {
  String get fullname => throw _privateConstructorUsedError; // t1_ or t4_
  InboxKind get kind => throw _privateConstructorUsedError;
  String get author => throw _privateConstructorUsedError;
  String get subject => throw _privateConstructorUsedError;
  String get body => throw _privateConstructorUsedError;
  DateTime get created => throw _privateConstructorUsedError;
  bool get isNew => throw _privateConstructorUsedError;
  String? get context =>
      throw _privateConstructorUsedError; // permalink for comment replies/mentions
  String? get linkTitle => throw _privateConstructorUsedError;
  String? get subreddit => throw _privateConstructorUsedError;
  String? get dest => throw _privateConstructorUsedError;
  List<InboxItem> get replies => throw _privateConstructorUsedError;

  /// Create a copy of InboxItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $InboxItemCopyWith<InboxItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $InboxItemCopyWith<$Res> {
  factory $InboxItemCopyWith(InboxItem value, $Res Function(InboxItem) then) =
      _$InboxItemCopyWithImpl<$Res, InboxItem>;
  @useResult
  $Res call({
    String fullname,
    InboxKind kind,
    String author,
    String subject,
    String body,
    DateTime created,
    bool isNew,
    String? context,
    String? linkTitle,
    String? subreddit,
    String? dest,
    List<InboxItem> replies,
  });
}

/// @nodoc
class _$InboxItemCopyWithImpl<$Res, $Val extends InboxItem>
    implements $InboxItemCopyWith<$Res> {
  _$InboxItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of InboxItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? fullname = null,
    Object? kind = null,
    Object? author = null,
    Object? subject = null,
    Object? body = null,
    Object? created = null,
    Object? isNew = null,
    Object? context = freezed,
    Object? linkTitle = freezed,
    Object? subreddit = freezed,
    Object? dest = freezed,
    Object? replies = null,
  }) {
    return _then(
      _value.copyWith(
            fullname: null == fullname
                ? _value.fullname
                : fullname // ignore: cast_nullable_to_non_nullable
                      as String,
            kind: null == kind
                ? _value.kind
                : kind // ignore: cast_nullable_to_non_nullable
                      as InboxKind,
            author: null == author
                ? _value.author
                : author // ignore: cast_nullable_to_non_nullable
                      as String,
            subject: null == subject
                ? _value.subject
                : subject // ignore: cast_nullable_to_non_nullable
                      as String,
            body: null == body
                ? _value.body
                : body // ignore: cast_nullable_to_non_nullable
                      as String,
            created: null == created
                ? _value.created
                : created // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            isNew: null == isNew
                ? _value.isNew
                : isNew // ignore: cast_nullable_to_non_nullable
                      as bool,
            context: freezed == context
                ? _value.context
                : context // ignore: cast_nullable_to_non_nullable
                      as String?,
            linkTitle: freezed == linkTitle
                ? _value.linkTitle
                : linkTitle // ignore: cast_nullable_to_non_nullable
                      as String?,
            subreddit: freezed == subreddit
                ? _value.subreddit
                : subreddit // ignore: cast_nullable_to_non_nullable
                      as String?,
            dest: freezed == dest
                ? _value.dest
                : dest // ignore: cast_nullable_to_non_nullable
                      as String?,
            replies: null == replies
                ? _value.replies
                : replies // ignore: cast_nullable_to_non_nullable
                      as List<InboxItem>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$InboxItemImplCopyWith<$Res>
    implements $InboxItemCopyWith<$Res> {
  factory _$$InboxItemImplCopyWith(
    _$InboxItemImpl value,
    $Res Function(_$InboxItemImpl) then,
  ) = __$$InboxItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String fullname,
    InboxKind kind,
    String author,
    String subject,
    String body,
    DateTime created,
    bool isNew,
    String? context,
    String? linkTitle,
    String? subreddit,
    String? dest,
    List<InboxItem> replies,
  });
}

/// @nodoc
class __$$InboxItemImplCopyWithImpl<$Res>
    extends _$InboxItemCopyWithImpl<$Res, _$InboxItemImpl>
    implements _$$InboxItemImplCopyWith<$Res> {
  __$$InboxItemImplCopyWithImpl(
    _$InboxItemImpl _value,
    $Res Function(_$InboxItemImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of InboxItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? fullname = null,
    Object? kind = null,
    Object? author = null,
    Object? subject = null,
    Object? body = null,
    Object? created = null,
    Object? isNew = null,
    Object? context = freezed,
    Object? linkTitle = freezed,
    Object? subreddit = freezed,
    Object? dest = freezed,
    Object? replies = null,
  }) {
    return _then(
      _$InboxItemImpl(
        fullname: null == fullname
            ? _value.fullname
            : fullname // ignore: cast_nullable_to_non_nullable
                  as String,
        kind: null == kind
            ? _value.kind
            : kind // ignore: cast_nullable_to_non_nullable
                  as InboxKind,
        author: null == author
            ? _value.author
            : author // ignore: cast_nullable_to_non_nullable
                  as String,
        subject: null == subject
            ? _value.subject
            : subject // ignore: cast_nullable_to_non_nullable
                  as String,
        body: null == body
            ? _value.body
            : body // ignore: cast_nullable_to_non_nullable
                  as String,
        created: null == created
            ? _value.created
            : created // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        isNew: null == isNew
            ? _value.isNew
            : isNew // ignore: cast_nullable_to_non_nullable
                  as bool,
        context: freezed == context
            ? _value.context
            : context // ignore: cast_nullable_to_non_nullable
                  as String?,
        linkTitle: freezed == linkTitle
            ? _value.linkTitle
            : linkTitle // ignore: cast_nullable_to_non_nullable
                  as String?,
        subreddit: freezed == subreddit
            ? _value.subreddit
            : subreddit // ignore: cast_nullable_to_non_nullable
                  as String?,
        dest: freezed == dest
            ? _value.dest
            : dest // ignore: cast_nullable_to_non_nullable
                  as String?,
        replies: null == replies
            ? _value._replies
            : replies // ignore: cast_nullable_to_non_nullable
                  as List<InboxItem>,
      ),
    );
  }
}

/// @nodoc

class _$InboxItemImpl extends _InboxItem {
  const _$InboxItemImpl({
    required this.fullname,
    required this.kind,
    required this.author,
    required this.subject,
    required this.body,
    required this.created,
    this.isNew = false,
    this.context,
    this.linkTitle,
    this.subreddit,
    this.dest,
    final List<InboxItem> replies = const <InboxItem>[],
  }) : _replies = replies,
       super._();

  @override
  final String fullname;
  // t1_ or t4_
  @override
  final InboxKind kind;
  @override
  final String author;
  @override
  final String subject;
  @override
  final String body;
  @override
  final DateTime created;
  @override
  @JsonKey()
  final bool isNew;
  @override
  final String? context;
  // permalink for comment replies/mentions
  @override
  final String? linkTitle;
  @override
  final String? subreddit;
  @override
  final String? dest;
  final List<InboxItem> _replies;
  @override
  @JsonKey()
  List<InboxItem> get replies {
    if (_replies is EqualUnmodifiableListView) return _replies;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_replies);
  }

  @override
  String toString() {
    return 'InboxItem(fullname: $fullname, kind: $kind, author: $author, subject: $subject, body: $body, created: $created, isNew: $isNew, context: $context, linkTitle: $linkTitle, subreddit: $subreddit, dest: $dest, replies: $replies)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$InboxItemImpl &&
            (identical(other.fullname, fullname) ||
                other.fullname == fullname) &&
            (identical(other.kind, kind) || other.kind == kind) &&
            (identical(other.author, author) || other.author == author) &&
            (identical(other.subject, subject) || other.subject == subject) &&
            (identical(other.body, body) || other.body == body) &&
            (identical(other.created, created) || other.created == created) &&
            (identical(other.isNew, isNew) || other.isNew == isNew) &&
            (identical(other.context, context) || other.context == context) &&
            (identical(other.linkTitle, linkTitle) ||
                other.linkTitle == linkTitle) &&
            (identical(other.subreddit, subreddit) ||
                other.subreddit == subreddit) &&
            (identical(other.dest, dest) || other.dest == dest) &&
            const DeepCollectionEquality().equals(other._replies, _replies));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    fullname,
    kind,
    author,
    subject,
    body,
    created,
    isNew,
    context,
    linkTitle,
    subreddit,
    dest,
    const DeepCollectionEquality().hash(_replies),
  );

  /// Create a copy of InboxItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$InboxItemImplCopyWith<_$InboxItemImpl> get copyWith =>
      __$$InboxItemImplCopyWithImpl<_$InboxItemImpl>(this, _$identity);
}

abstract class _InboxItem extends InboxItem {
  const factory _InboxItem({
    required final String fullname,
    required final InboxKind kind,
    required final String author,
    required final String subject,
    required final String body,
    required final DateTime created,
    final bool isNew,
    final String? context,
    final String? linkTitle,
    final String? subreddit,
    final String? dest,
    final List<InboxItem> replies,
  }) = _$InboxItemImpl;
  const _InboxItem._() : super._();

  @override
  String get fullname; // t1_ or t4_
  @override
  InboxKind get kind;
  @override
  String get author;
  @override
  String get subject;
  @override
  String get body;
  @override
  DateTime get created;
  @override
  bool get isNew;
  @override
  String? get context; // permalink for comment replies/mentions
  @override
  String? get linkTitle;
  @override
  String? get subreddit;
  @override
  String? get dest;
  @override
  List<InboxItem> get replies;

  /// Create a copy of InboxItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$InboxItemImplCopyWith<_$InboxItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
