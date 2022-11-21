// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target

part of 'error_response.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#custom-getters-and-methods');

ServerError _$ServerErrorFromJson(Map<String, dynamic> json) {
  return _ServerError.fromJson(json);
}

/// @nodoc
mixin _$ServerError {
  String get type => throw _privateConstructorUsedError;
  IList<ErrorItem> get errors => throw _privateConstructorUsedError;
  int get code => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
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
abstract class _$$_ServerErrorCopyWith<$Res>
    implements $ServerErrorCopyWith<$Res> {
  factory _$$_ServerErrorCopyWith(
          _$_ServerError value, $Res Function(_$_ServerError) then) =
      __$$_ServerErrorCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String type, IList<ErrorItem> errors, int code});
}

/// @nodoc
class __$$_ServerErrorCopyWithImpl<$Res>
    extends _$ServerErrorCopyWithImpl<$Res, _$_ServerError>
    implements _$$_ServerErrorCopyWith<$Res> {
  __$$_ServerErrorCopyWithImpl(
      _$_ServerError _value, $Res Function(_$_ServerError) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? errors = null,
    Object? code = null,
  }) {
    return _then(_$_ServerError(
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
class _$_ServerError implements _ServerError {
  _$_ServerError(
      {required this.type, required this.errors, required this.code});

  factory _$_ServerError.fromJson(Map<String, dynamic> json) =>
      _$$_ServerErrorFromJson(json);

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
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$_ServerError &&
            (identical(other.type, type) || other.type == type) &&
            const DeepCollectionEquality().equals(other.errors, errors) &&
            (identical(other.code, code) || other.code == code));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, type, const DeepCollectionEquality().hash(errors), code);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$_ServerErrorCopyWith<_$_ServerError> get copyWith =>
      __$$_ServerErrorCopyWithImpl<_$_ServerError>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$_ServerErrorToJson(
      this,
    );
  }
}

abstract class _ServerError implements ServerError {
  factory _ServerError(
      {required final String type,
      required final IList<ErrorItem> errors,
      required final int code}) = _$_ServerError;

  factory _ServerError.fromJson(Map<String, dynamic> json) =
      _$_ServerError.fromJson;

  @override
  String get type;
  @override
  IList<ErrorItem> get errors;
  @override
  int get code;
  @override
  @JsonKey(ignore: true)
  _$$_ServerErrorCopyWith<_$_ServerError> get copyWith =>
      throw _privateConstructorUsedError;
}

ErrorItem _$ErrorItemFromJson(Map<String, dynamic> json) {
  return _ErrorItem.fromJson(json);
}

/// @nodoc
mixin _$ErrorItem {
  String? get source => throw _privateConstructorUsedError;
  String get detail => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
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
abstract class _$$_ErrorItemCopyWith<$Res> implements $ErrorItemCopyWith<$Res> {
  factory _$$_ErrorItemCopyWith(
          _$_ErrorItem value, $Res Function(_$_ErrorItem) then) =
      __$$_ErrorItemCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? source, String detail});
}

/// @nodoc
class __$$_ErrorItemCopyWithImpl<$Res>
    extends _$ErrorItemCopyWithImpl<$Res, _$_ErrorItem>
    implements _$$_ErrorItemCopyWith<$Res> {
  __$$_ErrorItemCopyWithImpl(
      _$_ErrorItem _value, $Res Function(_$_ErrorItem) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? source = freezed,
    Object? detail = null,
  }) {
    return _then(_$_ErrorItem(
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
class _$_ErrorItem implements _ErrorItem {
  _$_ErrorItem({required this.source, required this.detail});

  factory _$_ErrorItem.fromJson(Map<String, dynamic> json) =>
      _$$_ErrorItemFromJson(json);

  @override
  final String? source;
  @override
  final String detail;

  @override
  String toString() {
    return 'ErrorItem(source: $source, detail: $detail)';
  }

  @override
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$_ErrorItem &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.detail, detail) || other.detail == detail));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, source, detail);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$_ErrorItemCopyWith<_$_ErrorItem> get copyWith =>
      __$$_ErrorItemCopyWithImpl<_$_ErrorItem>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$_ErrorItemToJson(
      this,
    );
  }
}

abstract class _ErrorItem implements ErrorItem {
  factory _ErrorItem(
      {required final String? source,
      required final String detail}) = _$_ErrorItem;

  factory _ErrorItem.fromJson(Map<String, dynamic> json) =
      _$_ErrorItem.fromJson;

  @override
  String? get source;
  @override
  String get detail;
  @override
  @JsonKey(ignore: true)
  _$$_ErrorItemCopyWith<_$_ErrorItem> get copyWith =>
      throw _privateConstructorUsedError;
}
