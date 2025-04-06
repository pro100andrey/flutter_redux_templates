// dart format width=80
// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'log_in_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LogInState {

 String? get email; String? get password;
/// Create a copy of LogInState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LogInStateCopyWith<LogInState> get copyWith => _$LogInStateCopyWithImpl<LogInState>(this as LogInState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LogInState&&(identical(other.email, email) || other.email == email)&&(identical(other.password, password) || other.password == password));
}


@override
int get hashCode => Object.hash(runtimeType,email,password);

@override
String toString() {
  return 'LogInState(email: $email, password: $password)';
}


}

/// @nodoc
abstract mixin class $LogInStateCopyWith<$Res>  {
  factory $LogInStateCopyWith(LogInState value, $Res Function(LogInState) _then) = _$LogInStateCopyWithImpl;
@useResult
$Res call({
 String? email, String? password
});




}
/// @nodoc
class _$LogInStateCopyWithImpl<$Res>
    implements $LogInStateCopyWith<$Res> {
  _$LogInStateCopyWithImpl(this._self, this._then);

  final LogInState _self;
  final $Res Function(LogInState) _then;

/// Create a copy of LogInState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? email = freezed,Object? password = freezed,}) {
  return _then(_self.copyWith(
email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,password: freezed == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// @nodoc


class _LogInState implements LogInState {
  const _LogInState({this.email, this.password});
  

@override final  String? email;
@override final  String? password;

/// Create a copy of LogInState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LogInStateCopyWith<_LogInState> get copyWith => __$LogInStateCopyWithImpl<_LogInState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LogInState&&(identical(other.email, email) || other.email == email)&&(identical(other.password, password) || other.password == password));
}


@override
int get hashCode => Object.hash(runtimeType,email,password);

@override
String toString() {
  return 'LogInState(email: $email, password: $password)';
}


}

/// @nodoc
abstract mixin class _$LogInStateCopyWith<$Res> implements $LogInStateCopyWith<$Res> {
  factory _$LogInStateCopyWith(_LogInState value, $Res Function(_LogInState) _then) = __$LogInStateCopyWithImpl;
@override @useResult
$Res call({
 String? email, String? password
});




}
/// @nodoc
class __$LogInStateCopyWithImpl<$Res>
    implements _$LogInStateCopyWith<$Res> {
  __$LogInStateCopyWithImpl(this._self, this._then);

  final _LogInState _self;
  final $Res Function(_LogInState) _then;

/// Create a copy of LogInState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? email = freezed,Object? password = freezed,}) {
  return _then(_LogInState(
email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,password: freezed == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
