// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'login_body.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

LoginBody _$LoginBodyFromJson(Map<String, dynamic> json) {
  return _LoginBody.fromJson(json);
}

/// @nodoc
mixin _$LoginBody {
  String get email => throw _privateConstructorUsedError;
  String get password => throw _privateConstructorUsedError;

  /// Serializes this LoginBody to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of LoginBody
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $LoginBodyCopyWith<LoginBody> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $LoginBodyCopyWith<$Res> {
  factory $LoginBodyCopyWith(LoginBody value, $Res Function(LoginBody) then) =
      _$LoginBodyCopyWithImpl<$Res, LoginBody>;
  @useResult
  $Res call({String email, String password});
}

/// @nodoc
class _$LoginBodyCopyWithImpl<$Res, $Val extends LoginBody>
    implements $LoginBodyCopyWith<$Res> {
  _$LoginBodyCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of LoginBody
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? email = null,
    Object? password = null,
  }) {
    return _then(_value.copyWith(
      email: null == email
          ? _value.email
          : email // ignore: cast_nullable_to_non_nullable
              as String,
      password: null == password
          ? _value.password
          : password // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$LoginBodyImplCopyWith<$Res>
    implements $LoginBodyCopyWith<$Res> {
  factory _$$LoginBodyImplCopyWith(
          _$LoginBodyImpl value, $Res Function(_$LoginBodyImpl) then) =
      __$$LoginBodyImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String email, String password});
}

/// @nodoc
class __$$LoginBodyImplCopyWithImpl<$Res>
    extends _$LoginBodyCopyWithImpl<$Res, _$LoginBodyImpl>
    implements _$$LoginBodyImplCopyWith<$Res> {
  __$$LoginBodyImplCopyWithImpl(
      _$LoginBodyImpl _value, $Res Function(_$LoginBodyImpl) _then)
      : super(_value, _then);

  /// Create a copy of LoginBody
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? email = null,
    Object? password = null,
  }) {
    return _then(_$LoginBodyImpl(
      email: null == email
          ? _value.email
          : email // ignore: cast_nullable_to_non_nullable
              as String,
      password: null == password
          ? _value.password
          : password // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$LoginBodyImpl implements _LoginBody {
  _$LoginBodyImpl({required this.email, required this.password});

  factory _$LoginBodyImpl.fromJson(Map<String, dynamic> json) =>
      _$$LoginBodyImplFromJson(json);

  @override
  final String email;
  @override
  final String password;

  @override
  String toString() {
    return 'LoginBody(email: $email, password: $password)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LoginBodyImpl &&
            (identical(other.email, email) || other.email == email) &&
            (identical(other.password, password) ||
                other.password == password));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, email, password);

  /// Create a copy of LoginBody
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$LoginBodyImplCopyWith<_$LoginBodyImpl> get copyWith =>
      __$$LoginBodyImplCopyWithImpl<_$LoginBodyImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$LoginBodyImplToJson(
      this,
    );
  }
}

abstract class _LoginBody implements LoginBody {
  factory _LoginBody(
      {required final String email,
      required final String password}) = _$LoginBodyImpl;

  factory _LoginBody.fromJson(Map<String, dynamic> json) =
      _$LoginBodyImpl.fromJson;

  @override
  String get email;
  @override
  String get password;

  /// Create a copy of LoginBody
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$LoginBodyImplCopyWith<_$LoginBodyImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
