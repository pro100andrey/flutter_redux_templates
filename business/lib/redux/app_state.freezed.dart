// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target

part of 'app_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more informations: https://github.com/rrousselGit/freezed#custom-getters-and-methods');

/// @nodoc
class _$AppStateTearOff {
  const _$AppStateTearOff();

  _AppState call(
      {Wait wait = Wait.empty, required ConnectivityState connectivity}) {
    return _AppState(
      wait: wait,
      connectivity: connectivity,
    );
  }
}

/// @nodoc
const $AppState = _$AppStateTearOff();

/// @nodoc
mixin _$AppState {
  Wait get wait => throw _privateConstructorUsedError;
  ConnectivityState get connectivity => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $AppStateCopyWith<AppState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AppStateCopyWith<$Res> {
  factory $AppStateCopyWith(AppState value, $Res Function(AppState) then) =
      _$AppStateCopyWithImpl<$Res>;
  $Res call({Wait wait, ConnectivityState connectivity});

  $ConnectivityStateCopyWith<$Res> get connectivity;
}

/// @nodoc
class _$AppStateCopyWithImpl<$Res> implements $AppStateCopyWith<$Res> {
  _$AppStateCopyWithImpl(this._value, this._then);

  final AppState _value;
  // ignore: unused_field
  final $Res Function(AppState) _then;

  @override
  $Res call({
    Object? wait = freezed,
    Object? connectivity = freezed,
  }) {
    return _then(_value.copyWith(
      wait: wait == freezed
          ? _value.wait
          : wait // ignore: cast_nullable_to_non_nullable
              as Wait,
      connectivity: connectivity == freezed
          ? _value.connectivity
          : connectivity // ignore: cast_nullable_to_non_nullable
              as ConnectivityState,
    ));
  }

  @override
  $ConnectivityStateCopyWith<$Res> get connectivity {
    return $ConnectivityStateCopyWith<$Res>(_value.connectivity, (value) {
      return _then(_value.copyWith(connectivity: value));
    });
  }
}

/// @nodoc
abstract class _$AppStateCopyWith<$Res> implements $AppStateCopyWith<$Res> {
  factory _$AppStateCopyWith(_AppState value, $Res Function(_AppState) then) =
      __$AppStateCopyWithImpl<$Res>;
  @override
  $Res call({Wait wait, ConnectivityState connectivity});

  @override
  $ConnectivityStateCopyWith<$Res> get connectivity;
}

/// @nodoc
class __$AppStateCopyWithImpl<$Res> extends _$AppStateCopyWithImpl<$Res>
    implements _$AppStateCopyWith<$Res> {
  __$AppStateCopyWithImpl(_AppState _value, $Res Function(_AppState) _then)
      : super(_value, (v) => _then(v as _AppState));

  @override
  _AppState get _value => super._value as _AppState;

  @override
  $Res call({
    Object? wait = freezed,
    Object? connectivity = freezed,
  }) {
    return _then(_AppState(
      wait: wait == freezed
          ? _value.wait
          : wait // ignore: cast_nullable_to_non_nullable
              as Wait,
      connectivity: connectivity == freezed
          ? _value.connectivity
          : connectivity // ignore: cast_nullable_to_non_nullable
              as ConnectivityState,
    ));
  }
}

/// @nodoc

class _$_AppState implements _AppState {
  const _$_AppState({this.wait = Wait.empty, required this.connectivity});

  @JsonKey()
  @override
  final Wait wait;
  @override
  final ConnectivityState connectivity;

  @override
  String toString() {
    return 'AppState(wait: $wait, connectivity: $connectivity)';
  }

  @override
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AppState &&
            const DeepCollectionEquality().equals(other.wait, wait) &&
            const DeepCollectionEquality()
                .equals(other.connectivity, connectivity));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(wait),
      const DeepCollectionEquality().hash(connectivity));

  @JsonKey(ignore: true)
  @override
  _$AppStateCopyWith<_AppState> get copyWith =>
      __$AppStateCopyWithImpl<_AppState>(this, _$identity);
}

abstract class _AppState implements AppState {
  const factory _AppState(
      {Wait wait, required ConnectivityState connectivity}) = _$_AppState;

  @override
  Wait get wait;
  @override
  ConnectivityState get connectivity;
  @override
  @JsonKey(ignore: true)
  _$AppStateCopyWith<_AppState> get copyWith =>
      throw _privateConstructorUsedError;
}
