// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target

part of 'connectivity_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more informations: https://github.com/rrousselGit/freezed#custom-getters-and-methods');

/// @nodoc
class _$ConnectivityStateTearOff {
  const _$ConnectivityStateTearOff();

  _ConnectivityState call({bool isAvailable = true}) {
    return _ConnectivityState(
      isAvailable: isAvailable,
    );
  }
}

/// @nodoc
const $ConnectivityState = _$ConnectivityStateTearOff();

/// @nodoc
mixin _$ConnectivityState {
  bool get isAvailable => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $ConnectivityStateCopyWith<ConnectivityState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ConnectivityStateCopyWith<$Res> {
  factory $ConnectivityStateCopyWith(
          ConnectivityState value, $Res Function(ConnectivityState) then) =
      _$ConnectivityStateCopyWithImpl<$Res>;
  $Res call({bool isAvailable});
}

/// @nodoc
class _$ConnectivityStateCopyWithImpl<$Res>
    implements $ConnectivityStateCopyWith<$Res> {
  _$ConnectivityStateCopyWithImpl(this._value, this._then);

  final ConnectivityState _value;
  // ignore: unused_field
  final $Res Function(ConnectivityState) _then;

  @override
  $Res call({
    Object? isAvailable = freezed,
  }) {
    return _then(_value.copyWith(
      isAvailable: isAvailable == freezed
          ? _value.isAvailable
          : isAvailable // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
abstract class _$ConnectivityStateCopyWith<$Res>
    implements $ConnectivityStateCopyWith<$Res> {
  factory _$ConnectivityStateCopyWith(
          _ConnectivityState value, $Res Function(_ConnectivityState) then) =
      __$ConnectivityStateCopyWithImpl<$Res>;
  @override
  $Res call({bool isAvailable});
}

/// @nodoc
class __$ConnectivityStateCopyWithImpl<$Res>
    extends _$ConnectivityStateCopyWithImpl<$Res>
    implements _$ConnectivityStateCopyWith<$Res> {
  __$ConnectivityStateCopyWithImpl(
      _ConnectivityState _value, $Res Function(_ConnectivityState) _then)
      : super(_value, (v) => _then(v as _ConnectivityState));

  @override
  _ConnectivityState get _value => super._value as _ConnectivityState;

  @override
  $Res call({
    Object? isAvailable = freezed,
  }) {
    return _then(_ConnectivityState(
      isAvailable: isAvailable == freezed
          ? _value.isAvailable
          : isAvailable // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc

class _$_ConnectivityState implements _ConnectivityState {
  const _$_ConnectivityState({this.isAvailable = true});

  @JsonKey()
  @override
  final bool isAvailable;

  @override
  String toString() {
    return 'ConnectivityState(isAvailable: $isAvailable)';
  }

  @override
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ConnectivityState &&
            const DeepCollectionEquality()
                .equals(other.isAvailable, isAvailable));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, const DeepCollectionEquality().hash(isAvailable));

  @JsonKey(ignore: true)
  @override
  _$ConnectivityStateCopyWith<_ConnectivityState> get copyWith =>
      __$ConnectivityStateCopyWithImpl<_ConnectivityState>(this, _$identity);
}

abstract class _ConnectivityState implements ConnectivityState {
  const factory _ConnectivityState({bool isAvailable}) = _$_ConnectivityState;

  @override
  bool get isAvailable;
  @override
  @JsonKey(ignore: true)
  _$ConnectivityStateCopyWith<_ConnectivityState> get copyWith =>
      throw _privateConstructorUsedError;
}
