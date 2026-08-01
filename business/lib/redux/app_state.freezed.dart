// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
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

 ConnectivityState get connectivity; LoginState get login; RegistrationState get registration; ForgotPasswordState get forgotPassword; ResetPasswordState get resetPassword; SessionState get session; ThemeState get theme; LanguageState get language; Wait get wait;
/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppStateCopyWith<AppState> get copyWith => _$AppStateCopyWithImpl<AppState>(this as AppState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppState&&(identical(other.connectivity, connectivity) || other.connectivity == connectivity)&&(identical(other.login, login) || other.login == login)&&(identical(other.registration, registration) || other.registration == registration)&&(identical(other.forgotPassword, forgotPassword) || other.forgotPassword == forgotPassword)&&(identical(other.resetPassword, resetPassword) || other.resetPassword == resetPassword)&&(identical(other.session, session) || other.session == session)&&(identical(other.theme, theme) || other.theme == theme)&&(identical(other.language, language) || other.language == language)&&(identical(other.wait, wait) || other.wait == wait));
}


@override
int get hashCode => Object.hash(runtimeType,connectivity,login,registration,forgotPassword,resetPassword,session,theme,language,wait);

@override
String toString() {
  return 'AppState(connectivity: $connectivity, login: $login, registration: $registration, forgotPassword: $forgotPassword, resetPassword: $resetPassword, session: $session, theme: $theme, language: $language, wait: $wait)';
}


}

/// @nodoc
abstract mixin class $AppStateCopyWith<$Res>  {
  factory $AppStateCopyWith(AppState value, $Res Function(AppState) _then) = _$AppStateCopyWithImpl;
@useResult
$Res call({
 ConnectivityState connectivity, LoginState login, RegistrationState registration, ForgotPasswordState forgotPassword, ResetPasswordState resetPassword, SessionState session, ThemeState theme, LanguageState language, Wait wait
});


$ConnectivityStateCopyWith<$Res> get connectivity;$LoginStateCopyWith<$Res> get login;$RegistrationStateCopyWith<$Res> get registration;$ForgotPasswordStateCopyWith<$Res> get forgotPassword;$ResetPasswordStateCopyWith<$Res> get resetPassword;$SessionStateCopyWith<$Res> get session;$ThemeStateCopyWith<$Res> get theme;$LanguageStateCopyWith<$Res> get language;

}
/// @nodoc
class _$AppStateCopyWithImpl<$Res>
    implements $AppStateCopyWith<$Res> {
  _$AppStateCopyWithImpl(this._self, this._then);

  final AppState _self;
  final $Res Function(AppState) _then;

/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? connectivity = null,Object? login = null,Object? registration = null,Object? forgotPassword = null,Object? resetPassword = null,Object? session = null,Object? theme = null,Object? language = null,Object? wait = null,}) {
  return _then(_self.copyWith(
connectivity: null == connectivity ? _self.connectivity : connectivity // ignore: cast_nullable_to_non_nullable
as ConnectivityState,login: null == login ? _self.login : login // ignore: cast_nullable_to_non_nullable
as LoginState,registration: null == registration ? _self.registration : registration // ignore: cast_nullable_to_non_nullable
as RegistrationState,forgotPassword: null == forgotPassword ? _self.forgotPassword : forgotPassword // ignore: cast_nullable_to_non_nullable
as ForgotPasswordState,resetPassword: null == resetPassword ? _self.resetPassword : resetPassword // ignore: cast_nullable_to_non_nullable
as ResetPasswordState,session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as SessionState,theme: null == theme ? _self.theme : theme // ignore: cast_nullable_to_non_nullable
as ThemeState,language: null == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as LanguageState,wait: null == wait ? _self.wait : wait // ignore: cast_nullable_to_non_nullable
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
$LoginStateCopyWith<$Res> get login {
  
  return $LoginStateCopyWith<$Res>(_self.login, (value) {
    return _then(_self.copyWith(login: value));
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
}/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThemeStateCopyWith<$Res> get theme {
  
  return $ThemeStateCopyWith<$Res>(_self.theme, (value) {
    return _then(_self.copyWith(theme: value));
  });
}/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LanguageStateCopyWith<$Res> get language {
  
  return $LanguageStateCopyWith<$Res>(_self.language, (value) {
    return _then(_self.copyWith(language: value));
  });
}
}



/// @nodoc


class _AppState implements AppState {
  const _AppState({required this.connectivity, required this.login, required this.registration, required this.forgotPassword, required this.resetPassword, required this.session, required this.theme, required this.language, required this.wait});
  

@override final  ConnectivityState connectivity;
@override final  LoginState login;
@override final  RegistrationState registration;
@override final  ForgotPasswordState forgotPassword;
@override final  ResetPasswordState resetPassword;
@override final  SessionState session;
@override final  ThemeState theme;
@override final  LanguageState language;
@override final  Wait wait;

/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppStateCopyWith<_AppState> get copyWith => __$AppStateCopyWithImpl<_AppState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppState&&(identical(other.connectivity, connectivity) || other.connectivity == connectivity)&&(identical(other.login, login) || other.login == login)&&(identical(other.registration, registration) || other.registration == registration)&&(identical(other.forgotPassword, forgotPassword) || other.forgotPassword == forgotPassword)&&(identical(other.resetPassword, resetPassword) || other.resetPassword == resetPassword)&&(identical(other.session, session) || other.session == session)&&(identical(other.theme, theme) || other.theme == theme)&&(identical(other.language, language) || other.language == language)&&(identical(other.wait, wait) || other.wait == wait));
}


@override
int get hashCode => Object.hash(runtimeType,connectivity,login,registration,forgotPassword,resetPassword,session,theme,language,wait);

@override
String toString() {
  return 'AppState(connectivity: $connectivity, login: $login, registration: $registration, forgotPassword: $forgotPassword, resetPassword: $resetPassword, session: $session, theme: $theme, language: $language, wait: $wait)';
}


}

/// @nodoc
abstract mixin class _$AppStateCopyWith<$Res> implements $AppStateCopyWith<$Res> {
  factory _$AppStateCopyWith(_AppState value, $Res Function(_AppState) _then) = __$AppStateCopyWithImpl;
@override @useResult
$Res call({
 ConnectivityState connectivity, LoginState login, RegistrationState registration, ForgotPasswordState forgotPassword, ResetPasswordState resetPassword, SessionState session, ThemeState theme, LanguageState language, Wait wait
});


@override $ConnectivityStateCopyWith<$Res> get connectivity;@override $LoginStateCopyWith<$Res> get login;@override $RegistrationStateCopyWith<$Res> get registration;@override $ForgotPasswordStateCopyWith<$Res> get forgotPassword;@override $ResetPasswordStateCopyWith<$Res> get resetPassword;@override $SessionStateCopyWith<$Res> get session;@override $ThemeStateCopyWith<$Res> get theme;@override $LanguageStateCopyWith<$Res> get language;

}
/// @nodoc
class __$AppStateCopyWithImpl<$Res>
    implements _$AppStateCopyWith<$Res> {
  __$AppStateCopyWithImpl(this._self, this._then);

  final _AppState _self;
  final $Res Function(_AppState) _then;

/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? connectivity = null,Object? login = null,Object? registration = null,Object? forgotPassword = null,Object? resetPassword = null,Object? session = null,Object? theme = null,Object? language = null,Object? wait = null,}) {
  return _then(_AppState(
connectivity: null == connectivity ? _self.connectivity : connectivity // ignore: cast_nullable_to_non_nullable
as ConnectivityState,login: null == login ? _self.login : login // ignore: cast_nullable_to_non_nullable
as LoginState,registration: null == registration ? _self.registration : registration // ignore: cast_nullable_to_non_nullable
as RegistrationState,forgotPassword: null == forgotPassword ? _self.forgotPassword : forgotPassword // ignore: cast_nullable_to_non_nullable
as ForgotPasswordState,resetPassword: null == resetPassword ? _self.resetPassword : resetPassword // ignore: cast_nullable_to_non_nullable
as ResetPasswordState,session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as SessionState,theme: null == theme ? _self.theme : theme // ignore: cast_nullable_to_non_nullable
as ThemeState,language: null == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as LanguageState,wait: null == wait ? _self.wait : wait // ignore: cast_nullable_to_non_nullable
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
$LoginStateCopyWith<$Res> get login {
  
  return $LoginStateCopyWith<$Res>(_self.login, (value) {
    return _then(_self.copyWith(login: value));
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
}/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThemeStateCopyWith<$Res> get theme {
  
  return $ThemeStateCopyWith<$Res>(_self.theme, (value) {
    return _then(_self.copyWith(theme: value));
  });
}/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LanguageStateCopyWith<$Res> get language {
  
  return $LanguageStateCopyWith<$Res>(_self.language, (value) {
    return _then(_self.copyWith(language: value));
  });
}
}

// dart format on
