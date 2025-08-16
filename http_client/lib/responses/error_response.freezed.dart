// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error_response.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ServerError {

 String get type; IList<ErrorItem> get errors; int get code;
/// Create a copy of ServerError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ServerErrorCopyWith<ServerError> get copyWith => _$ServerErrorCopyWithImpl<ServerError>(this as ServerError, _$identity);

  /// Serializes this ServerError to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ServerError&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other.errors, errors)&&(identical(other.code, code) || other.code == code));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,const DeepCollectionEquality().hash(errors),code);

@override
String toString() {
  return 'ServerError(type: $type, errors: $errors, code: $code)';
}


}

/// @nodoc
abstract mixin class $ServerErrorCopyWith<$Res>  {
  factory $ServerErrorCopyWith(ServerError value, $Res Function(ServerError) _then) = _$ServerErrorCopyWithImpl;
@useResult
$Res call({
 String type, IList<ErrorItem> errors, int code
});




}
/// @nodoc
class _$ServerErrorCopyWithImpl<$Res>
    implements $ServerErrorCopyWith<$Res> {
  _$ServerErrorCopyWithImpl(this._self, this._then);

  final ServerError _self;
  final $Res Function(ServerError) _then;

/// Create a copy of ServerError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? errors = null,Object? code = null,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,errors: null == errors ? _self.errors : errors // ignore: cast_nullable_to_non_nullable
as IList<ErrorItem>,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}



/// @nodoc
@JsonSerializable()

class _ServerError implements ServerError {
   _ServerError({required this.type, required this.errors, required this.code});
  factory _ServerError.fromJson(Map<String, dynamic> json) => _$ServerErrorFromJson(json);

@override final  String type;
@override final  IList<ErrorItem> errors;
@override final  int code;

/// Create a copy of ServerError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ServerErrorCopyWith<_ServerError> get copyWith => __$ServerErrorCopyWithImpl<_ServerError>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ServerErrorToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ServerError&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other.errors, errors)&&(identical(other.code, code) || other.code == code));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,const DeepCollectionEquality().hash(errors),code);

@override
String toString() {
  return 'ServerError(type: $type, errors: $errors, code: $code)';
}


}

/// @nodoc
abstract mixin class _$ServerErrorCopyWith<$Res> implements $ServerErrorCopyWith<$Res> {
  factory _$ServerErrorCopyWith(_ServerError value, $Res Function(_ServerError) _then) = __$ServerErrorCopyWithImpl;
@override @useResult
$Res call({
 String type, IList<ErrorItem> errors, int code
});




}
/// @nodoc
class __$ServerErrorCopyWithImpl<$Res>
    implements _$ServerErrorCopyWith<$Res> {
  __$ServerErrorCopyWithImpl(this._self, this._then);

  final _ServerError _self;
  final $Res Function(_ServerError) _then;

/// Create a copy of ServerError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? errors = null,Object? code = null,}) {
  return _then(_ServerError(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,errors: null == errors ? _self.errors : errors // ignore: cast_nullable_to_non_nullable
as IList<ErrorItem>,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$ErrorItem {

 String? get source; String get detail;
/// Create a copy of ErrorItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ErrorItemCopyWith<ErrorItem> get copyWith => _$ErrorItemCopyWithImpl<ErrorItem>(this as ErrorItem, _$identity);

  /// Serializes this ErrorItem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorItem&&(identical(other.source, source) || other.source == source)&&(identical(other.detail, detail) || other.detail == detail));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,source,detail);

@override
String toString() {
  return 'ErrorItem(source: $source, detail: $detail)';
}


}

/// @nodoc
abstract mixin class $ErrorItemCopyWith<$Res>  {
  factory $ErrorItemCopyWith(ErrorItem value, $Res Function(ErrorItem) _then) = _$ErrorItemCopyWithImpl;
@useResult
$Res call({
 String? source, String detail
});




}
/// @nodoc
class _$ErrorItemCopyWithImpl<$Res>
    implements $ErrorItemCopyWith<$Res> {
  _$ErrorItemCopyWithImpl(this._self, this._then);

  final ErrorItem _self;
  final $Res Function(ErrorItem) _then;

/// Create a copy of ErrorItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = freezed,Object? detail = null,}) {
  return _then(_self.copyWith(
source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc
@JsonSerializable()

class _ErrorItem implements ErrorItem {
   _ErrorItem({required this.source, required this.detail});
  factory _ErrorItem.fromJson(Map<String, dynamic> json) => _$ErrorItemFromJson(json);

@override final  String? source;
@override final  String detail;

/// Create a copy of ErrorItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ErrorItemCopyWith<_ErrorItem> get copyWith => __$ErrorItemCopyWithImpl<_ErrorItem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ErrorItemToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ErrorItem&&(identical(other.source, source) || other.source == source)&&(identical(other.detail, detail) || other.detail == detail));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,source,detail);

@override
String toString() {
  return 'ErrorItem(source: $source, detail: $detail)';
}


}

/// @nodoc
abstract mixin class _$ErrorItemCopyWith<$Res> implements $ErrorItemCopyWith<$Res> {
  factory _$ErrorItemCopyWith(_ErrorItem value, $Res Function(_ErrorItem) _then) = __$ErrorItemCopyWithImpl;
@override @useResult
$Res call({
 String? source, String detail
});




}
/// @nodoc
class __$ErrorItemCopyWithImpl<$Res>
    implements _$ErrorItemCopyWith<$Res> {
  __$ErrorItemCopyWithImpl(this._self, this._then);

  final _ErrorItem _self;
  final $Res Function(_ErrorItem) _then;

/// Create a copy of ErrorItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = freezed,Object? detail = null,}) {
  return _then(_ErrorItem(
source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
