// dart format width=80
// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AppState {

 ConnectivityState get connectivity; LogInState get logIn; RegistrationState get registration; ForgotPasswordState get forgotPassword; ResetPasswordState get resetPassword; SessionState get session; Wait get wait;
/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppStateCopyWith<AppState> get copyWith => _$AppStateCopyWithImpl<AppState>(this as AppState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppState&&(identical(other.connectivity, connectivity) || other.connectivity == connectivity)&&(identical(other.logIn, logIn) || other.logIn == logIn)&&(identical(other.registration, registration) || other.registration == registration)&&(identical(other.forgotPassword, forgotPassword) || other.forgotPassword == forgotPassword)&&(identical(other.resetPassword, resetPassword) || other.resetPassword == resetPassword)&&(identical(other.session, session) || other.session == session)&&(identical(other.wait, wait) || other.wait == wait));
}


@override
int get hashCode => Object.hash(runtimeType,connectivity,logIn,registration,forgotPassword,resetPassword,session,wait);

@override
String toString() {
  return 'AppState(connectivity: $connectivity, logIn: $logIn, registration: $registration, forgotPassword: $forgotPassword, resetPassword: $resetPassword, session: $session, wait: $wait)';
}


}

/// @nodoc
abstract mixin class $AppStateCopyWith<$Res>  {
  factory $AppStateCopyWith(AppState value, $Res Function(AppState) _then) = _$AppStateCopyWithImpl;
@useResult
$Res call({
 ConnectivityState connectivity, LogInState logIn, RegistrationState registration, ForgotPasswordState forgotPassword, ResetPasswordState resetPassword, SessionState session, Wait wait
});


$ConnectivityStateCopyWith<$Res> get connectivity;$LogInStateCopyWith<$Res> get logIn;$RegistrationStateCopyWith<$Res> get registration;$ForgotPasswordStateCopyWith<$Res> get forgotPassword;$ResetPasswordStateCopyWith<$Res> get resetPassword;$SessionStateCopyWith<$Res> get session;

}
/// @nodoc
class _$AppStateCopyWithImpl<$Res>
    implements $AppStateCopyWith<$Res> {
  _$AppStateCopyWithImpl(this._self, this._then);

  final AppState _self;
  final $Res Function(AppState) _then;

/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? connectivity = null,Object? logIn = null,Object? registration = null,Object? forgotPassword = null,Object? resetPassword = null,Object? session = null,Object? wait = null,}) {
  return _then(_self.copyWith(
connectivity: null == connectivity ? _self.connectivity : connectivity // ignore: cast_nullable_to_non_nullable
as ConnectivityState,logIn: null == logIn ? _self.logIn : logIn // ignore: cast_nullable_to_non_nullable
as LogInState,registration: null == registration ? _self.registration : registration // ignore: cast_nullable_to_non_nullable
as RegistrationState,forgotPassword: null == forgotPassword ? _self.forgotPassword : forgotPassword // ignore: cast_nullable_to_non_nullable
as ForgotPasswordState,resetPassword: null == resetPassword ? _self.resetPassword : resetPassword // ignore: cast_nullable_to_non_nullable
as ResetPasswordState,session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as SessionState,wait: null == wait ? _self.wait : wait // ignore: cast_nullable_to_non_nullable
as Wait,
  ));
}
/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConnectivityStateCopyWith<$Res> get connectivity {
  
  return $ConnectivityStateCopyWith<$Res>(_self.connectivity, (value) {
    return _then(_self.copyWith(connectivity: value));
  });
}/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LogInStateCopyWith<$Res> get logIn {
  
  return $LogInStateCopyWith<$Res>(_self.logIn, (value) {
    return _then(_self.copyWith(logIn: value));
  });
}/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RegistrationStateCopyWith<$Res> get registration {
  
  return $RegistrationStateCopyWith<$Res>(_self.registration, (value) {
    return _then(_self.copyWith(registration: value));
  });
}/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ForgotPasswordStateCopyWith<$Res> get forgotPassword {
  
  return $ForgotPasswordStateCopyWith<$Res>(_self.forgotPassword, (value) {
    return _then(_self.copyWith(forgotPassword: value));
  });
}/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResetPasswordStateCopyWith<$Res> get resetPassword {
  
  return $ResetPasswordStateCopyWith<$Res>(_self.resetPassword, (value) {
    return _then(_self.copyWith(resetPassword: value));
  });
}/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionStateCopyWith<$Res> get session {
  
  return $SessionStateCopyWith<$Res>(_self.session, (value) {
    return _then(_self.copyWith(session: value));
  });
}
}


/// @nodoc


class _AppState implements AppState {
  const _AppState({required this.connectivity, required this.logIn, required this.registration, required this.forgotPassword, required this.resetPassword, required this.session, required this.wait});
  

@override final  ConnectivityState connectivity;
@override final  LogInState logIn;
@override final  RegistrationState registration;
@override final  ForgotPasswordState forgotPassword;
@override final  ResetPasswordState resetPassword;
@override final  SessionState session;
@override final  Wait wait;

/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppStateCopyWith<_AppState> get copyWith => __$AppStateCopyWithImpl<_AppState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppState&&(identical(other.connectivity, connectivity) || other.connectivity == connectivity)&&(identical(other.logIn, logIn) || other.logIn == logIn)&&(identical(other.registration, registration) || other.registration == registration)&&(identical(other.forgotPassword, forgotPassword) || other.forgotPassword == forgotPassword)&&(identical(other.resetPassword, resetPassword) || other.resetPassword == resetPassword)&&(identical(other.session, session) || other.session == session)&&(identical(other.wait, wait) || other.wait == wait));
}


@override
int get hashCode => Object.hash(runtimeType,connectivity,logIn,registration,forgotPassword,resetPassword,session,wait);

@override
String toString() {
  return 'AppState(connectivity: $connectivity, logIn: $logIn, registration: $registration, forgotPassword: $forgotPassword, resetPassword: $resetPassword, session: $session, wait: $wait)';
}


}

/// @nodoc
abstract mixin class _$AppStateCopyWith<$Res> implements $AppStateCopyWith<$Res> {
  factory _$AppStateCopyWith(_AppState value, $Res Function(_AppState) _then) = __$AppStateCopyWithImpl;
@override @useResult
$Res call({
 ConnectivityState connectivity, LogInState logIn, RegistrationState registration, ForgotPasswordState forgotPassword, ResetPasswordState resetPassword, SessionState session, Wait wait
});


@override $ConnectivityStateCopyWith<$Res> get connectivity;@override $LogInStateCopyWith<$Res> get logIn;@override $RegistrationStateCopyWith<$Res> get registration;@override $ForgotPasswordStateCopyWith<$Res> get forgotPassword;@override $ResetPasswordStateCopyWith<$Res> get resetPassword;@override $SessionStateCopyWith<$Res> get session;

}
/// @nodoc
class __$AppStateCopyWithImpl<$Res>
    implements _$AppStateCopyWith<$Res> {
  __$AppStateCopyWithImpl(this._self, this._then);

  final _AppState _self;
  final $Res Function(_AppState) _then;

/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? connectivity = null,Object? logIn = null,Object? registration = null,Object? forgotPassword = null,Object? resetPassword = null,Object? session = null,Object? wait = null,}) {
  return _then(_AppState(
connectivity: null == connectivity ? _self.connectivity : connectivity // ignore: cast_nullable_to_non_nullable
as ConnectivityState,logIn: null == logIn ? _self.logIn : logIn // ignore: cast_nullable_to_non_nullable
as LogInState,registration: null == registration ? _self.registration : registration // ignore: cast_nullable_to_non_nullable
as RegistrationState,forgotPassword: null == forgotPassword ? _self.forgotPassword : forgotPassword // ignore: cast_nullable_to_non_nullable
as ForgotPasswordState,resetPassword: null == resetPassword ? _self.resetPassword : resetPassword // ignore: cast_nullable_to_non_nullable
as ResetPasswordState,session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as SessionState,wait: null == wait ? _self.wait : wait // ignore: cast_nullable_to_non_nullable
as Wait,
  ));
}

/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConnectivityStateCopyWith<$Res> get connectivity {
  
  return $ConnectivityStateCopyWith<$Res>(_self.connectivity, (value) {
    return _then(_self.copyWith(connectivity: value));
  });
}/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LogInStateCopyWith<$Res> get logIn {
  
  return $LogInStateCopyWith<$Res>(_self.logIn, (value) {
    return _then(_self.copyWith(logIn: value));
  });
}/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RegistrationStateCopyWith<$Res> get registration {
  
  return $RegistrationStateCopyWith<$Res>(_self.registration, (value) {
    return _then(_self.copyWith(registration: value));
  });
}/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ForgotPasswordStateCopyWith<$Res> get forgotPassword {
  
  return $ForgotPasswordStateCopyWith<$Res>(_self.forgotPassword, (value) {
    return _then(_self.copyWith(forgotPassword: value));
  });
}/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResetPasswordStateCopyWith<$Res> get resetPassword {
  
  return $ResetPasswordStateCopyWith<$Res>(_self.resetPassword, (value) {
    return _then(_self.copyWith(resetPassword: value));
  });
}/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionStateCopyWith<$Res> get session {
  
  return $SessionStateCopyWith<$Res>(_self.session, (value) {
    return _then(_self.copyWith(session: value));
  });
}
}

// dart format on
