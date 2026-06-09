// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'reddit_user.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$RedditUser {
  String get name => throw _privateConstructorUsedError;
  String? get iconUrl => throw _privateConstructorUsedError;
  String? get bannerUrl => throw _privateConstructorUsedError;
  int get linkKarma => throw _privateConstructorUsedError;
  int get commentKarma => throw _privateConstructorUsedError;
  DateTime get created => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;

  /// Create a copy of RedditUser
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RedditUserCopyWith<RedditUser> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RedditUserCopyWith<$Res> {
  factory $RedditUserCopyWith(
    RedditUser value,
    $Res Function(RedditUser) then,
  ) = _$RedditUserCopyWithImpl<$Res, RedditUser>;
  @useResult
  $Res call({
    String name,
    String? iconUrl,
    String? bannerUrl,
    int linkKarma,
    int commentKarma,
    DateTime created,
    String description,
  });
}

/// @nodoc
class _$RedditUserCopyWithImpl<$Res, $Val extends RedditUser>
    implements $RedditUserCopyWith<$Res> {
  _$RedditUserCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of RedditUser
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? iconUrl = freezed,
    Object? bannerUrl = freezed,
    Object? linkKarma = null,
    Object? commentKarma = null,
    Object? created = null,
    Object? description = null,
  }) {
    return _then(
      _value.copyWith(
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            iconUrl: freezed == iconUrl
                ? _value.iconUrl
                : iconUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            bannerUrl: freezed == bannerUrl
                ? _value.bannerUrl
                : bannerUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            linkKarma: null == linkKarma
                ? _value.linkKarma
                : linkKarma // ignore: cast_nullable_to_non_nullable
                      as int,
            commentKarma: null == commentKarma
                ? _value.commentKarma
                : commentKarma // ignore: cast_nullable_to_non_nullable
                      as int,
            created: null == created
                ? _value.created
                : created // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            description: null == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$RedditUserImplCopyWith<$Res>
    implements $RedditUserCopyWith<$Res> {
  factory _$$RedditUserImplCopyWith(
    _$RedditUserImpl value,
    $Res Function(_$RedditUserImpl) then,
  ) = __$$RedditUserImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String name,
    String? iconUrl,
    String? bannerUrl,
    int linkKarma,
    int commentKarma,
    DateTime created,
    String description,
  });
}

/// @nodoc
class __$$RedditUserImplCopyWithImpl<$Res>
    extends _$RedditUserCopyWithImpl<$Res, _$RedditUserImpl>
    implements _$$RedditUserImplCopyWith<$Res> {
  __$$RedditUserImplCopyWithImpl(
    _$RedditUserImpl _value,
    $Res Function(_$RedditUserImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of RedditUser
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? iconUrl = freezed,
    Object? bannerUrl = freezed,
    Object? linkKarma = null,
    Object? commentKarma = null,
    Object? created = null,
    Object? description = null,
  }) {
    return _then(
      _$RedditUserImpl(
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        iconUrl: freezed == iconUrl
            ? _value.iconUrl
            : iconUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        bannerUrl: freezed == bannerUrl
            ? _value.bannerUrl
            : bannerUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        linkKarma: null == linkKarma
            ? _value.linkKarma
            : linkKarma // ignore: cast_nullable_to_non_nullable
                  as int,
        commentKarma: null == commentKarma
            ? _value.commentKarma
            : commentKarma // ignore: cast_nullable_to_non_nullable
                  as int,
        created: null == created
            ? _value.created
            : created // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        description: null == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$RedditUserImpl extends _RedditUser {
  const _$RedditUserImpl({
    required this.name,
    this.iconUrl,
    this.bannerUrl,
    this.linkKarma = 0,
    this.commentKarma = 0,
    required this.created,
    this.description = '',
  }) : super._();

  @override
  final String name;
  @override
  final String? iconUrl;
  @override
  final String? bannerUrl;
  @override
  @JsonKey()
  final int linkKarma;
  @override
  @JsonKey()
  final int commentKarma;
  @override
  final DateTime created;
  @override
  @JsonKey()
  final String description;

  @override
  String toString() {
    return 'RedditUser(name: $name, iconUrl: $iconUrl, bannerUrl: $bannerUrl, linkKarma: $linkKarma, commentKarma: $commentKarma, created: $created, description: $description)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RedditUserImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.iconUrl, iconUrl) || other.iconUrl == iconUrl) &&
            (identical(other.bannerUrl, bannerUrl) ||
                other.bannerUrl == bannerUrl) &&
            (identical(other.linkKarma, linkKarma) ||
                other.linkKarma == linkKarma) &&
            (identical(other.commentKarma, commentKarma) ||
                other.commentKarma == commentKarma) &&
            (identical(other.created, created) || other.created == created) &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    name,
    iconUrl,
    bannerUrl,
    linkKarma,
    commentKarma,
    created,
    description,
  );

  /// Create a copy of RedditUser
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RedditUserImplCopyWith<_$RedditUserImpl> get copyWith =>
      __$$RedditUserImplCopyWithImpl<_$RedditUserImpl>(this, _$identity);
}

abstract class _RedditUser extends RedditUser {
  const factory _RedditUser({
    required final String name,
    final String? iconUrl,
    final String? bannerUrl,
    final int linkKarma,
    final int commentKarma,
    required final DateTime created,
    final String description,
  }) = _$RedditUserImpl;
  const _RedditUser._() : super._();

  @override
  String get name;
  @override
  String? get iconUrl;
  @override
  String? get bannerUrl;
  @override
  int get linkKarma;
  @override
  int get commentKarma;
  @override
  DateTime get created;
  @override
  String get description;

  /// Create a copy of RedditUser
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RedditUserImplCopyWith<_$RedditUserImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
