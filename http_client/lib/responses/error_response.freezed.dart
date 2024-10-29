// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error_response.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ServerError _$ServerErrorFromJson(Map<String, dynamic> json) {
  return _ServerError.fromJson(json);
}

/// @nodoc
mixin _$ServerError {
  String get type => throw _privateConstructorUsedError;
  IList<ErrorItem> get errors => throw _privateConstructorUsedError;
  int get code => throw _privateConstructorUsedError;

  /// Serializes this ServerError to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ServerError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ServerErrorCopyWith<ServerError> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ServerErrorCopyWith<$Res> {
  factory $ServerErrorCopyWith(
          ServerError value, $Res Function(ServerError) then) =
      _$ServerErrorCopyWithImpl<$Res, ServerError>;
  @useResult
  $Res call({String type, IList<ErrorItem> errors, int code});
}

/// @nodoc
class _$ServerErrorCopyWithImpl<$Res, $Val extends ServerError>
    implements $ServerErrorCopyWith<$Res> {
  _$ServerErrorCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ServerError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? errors = null,
    Object? code = null,
  }) {
    return _then(_value.copyWith(
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      errors: null == errors
          ? _value.errors
          : errors // ignore: cast_nullable_to_non_nullable
              as IList<ErrorItem>,
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ServerErrorImplCopyWith<$Res>
    implements $ServerErrorCopyWith<$Res> {
  factory _$$ServerErrorImplCopyWith(
          _$ServerErrorImpl value, $Res Function(_$ServerErrorImpl) then) =
      __$$ServerErrorImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String type, IList<ErrorItem> errors, int code});
}

/// @nodoc
class __$$ServerErrorImplCopyWithImpl<$Res>
    extends _$ServerErrorCopyWithImpl<$Res, _$ServerErrorImpl>
    implements _$$ServerErrorImplCopyWith<$Res> {
  __$$ServerErrorImplCopyWithImpl(
      _$ServerErrorImpl _value, $Res Function(_$ServerErrorImpl) _then)
      : super(_value, _then);

  /// Create a copy of ServerError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? errors = null,
    Object? code = null,
  }) {
    return _then(_$ServerErrorImpl(
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      errors: null == errors
          ? _value.errors
          : errors // ignore: cast_nullable_to_non_nullable
              as IList<ErrorItem>,
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ServerErrorImpl implements _ServerError {
  _$ServerErrorImpl(
      {required this.type, required this.errors, required this.code});

  factory _$ServerErrorImpl.fromJson(Map<String, dynamic> json) =>
      _$$ServerErrorImplFromJson(json);

  @override
  final String type;
  @override
  final IList<ErrorItem> errors;
  @override
  final int code;

  @override
  String toString() {
    return 'ServerError(type: $type, errors: $errors, code: $code)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ServerErrorImpl &&
            (identical(other.type, type) || other.type == type) &&
            const DeepCollectionEquality().equals(other.errors, errors) &&
            (identical(other.code, code) || other.code == code));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, type, const DeepCollectionEquality().hash(errors), code);

  /// Create a copy of ServerError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ServerErrorImplCopyWith<_$ServerErrorImpl> get copyWith =>
      __$$ServerErrorImplCopyWithImpl<_$ServerErrorImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ServerErrorImplToJson(
      this,
    );
  }
}

abstract class _ServerError implements ServerError {
  factory _ServerError(
      {required final String type,
      required final IList<ErrorItem> errors,
      required final int code}) = _$ServerErrorImpl;

  factory _ServerError.fromJson(Map<String, dynamic> json) =
      _$ServerErrorImpl.fromJson;

  @override
  String get type;
  @override
  IList<ErrorItem> get errors;
  @override
  int get code;

  /// Create a copy of ServerError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ServerErrorImplCopyWith<_$ServerErrorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ErrorItem _$ErrorItemFromJson(Map<String, dynamic> json) {
  return _ErrorItem.fromJson(json);
}

/// @nodoc
mixin _$ErrorItem {
  String? get source => throw _privateConstructorUsedError;
  String get detail => throw _privateConstructorUsedError;

  /// Serializes this ErrorItem to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ErrorItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ErrorItemCopyWith<ErrorItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ErrorItemCopyWith<$Res> {
  factory $ErrorItemCopyWith(ErrorItem value, $Res Function(ErrorItem) then) =
      _$ErrorItemCopyWithImpl<$Res, ErrorItem>;
  @useResult
  $Res call({String? source, String detail});
}

/// @nodoc
class _$ErrorItemCopyWithImpl<$Res, $Val extends ErrorItem>
    implements $ErrorItemCopyWith<$Res> {
  _$ErrorItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ErrorItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? source = freezed,
    Object? detail = null,
  }) {
    return _then(_value.copyWith(
      source: freezed == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as String?,
      detail: null == detail
          ? _value.detail
          : detail // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ErrorItemImplCopyWith<$Res>
    implements $ErrorItemCopyWith<$Res> {
  factory _$$ErrorItemImplCopyWith(
          _$ErrorItemImpl value, $Res Function(_$ErrorItemImpl) then) =
      __$$ErrorItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? source, String detail});
}

/// @nodoc
class __$$ErrorItemImplCopyWithImpl<$Res>
    extends _$ErrorItemCopyWithImpl<$Res, _$ErrorItemImpl>
    implements _$$ErrorItemImplCopyWith<$Res> {
  __$$ErrorItemImplCopyWithImpl(
      _$ErrorItemImpl _value, $Res Function(_$ErrorItemImpl) _then)
      : super(_value, _then);

  /// Create a copy of ErrorItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? source = freezed,
    Object? detail = null,
  }) {
    return _then(_$ErrorItemImpl(
      source: freezed == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as String?,
      detail: null == detail
          ? _value.detail
          : detail // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ErrorItemImpl implements _ErrorItem {
  _$ErrorItemImpl({required this.source, required this.detail});

  factory _$ErrorItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$ErrorItemImplFromJson(json);

  @override
  final String? source;
  @override
  final String detail;

  @override
  String toString() {
    return 'ErrorItem(source: $source, detail: $detail)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ErrorItemImpl &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.detail, detail) || other.detail == detail));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, source, detail);

  /// Create a copy of ErrorItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ErrorItemImplCopyWith<_$ErrorItemImpl> get copyWith =>
      __$$ErrorItemImplCopyWithImpl<_$ErrorItemImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ErrorItemImplToJson(
      this,
    );
  }
}

abstract class _ErrorItem implements ErrorItem {
  factory _ErrorItem(
      {required final String? source,
      required final String detail}) = _$ErrorItemImpl;

  factory _ErrorItem.fromJson(Map<String, dynamic> json) =
      _$ErrorItemImpl.fromJson;

  @override
  String? get source;
  @override
  String get detail;

  /// Create a copy of ErrorItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ErrorItemImplCopyWith<_$ErrorItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
