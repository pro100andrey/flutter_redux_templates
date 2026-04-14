import 'dart:async';

import 'package:equatable/equatable.dart';

typedef VoidCallbackVm = FutureOr Function(void);

sealed class BaseValueChangedVm<T> extends Equatable {
  BaseValueChangedVm({
    FutureOr Function(T value)? onChanged,
    this.enabled = true,
  }) : _onChanged =
           onChanged ??
           ((value) => throw Exception('onChanged is not implemented.'));

  final bool enabled;
  //
  // ignore: unsafe_variance
  final FutureOr Function(T value) _onChanged;

  void onChangedSync(covariant T value) {
    if (!_ifActionIsSync(_onChanged)) {
      throw Exception(
        "Can't onChangedSync(${value.runtimeType}) "
        'because ${value.runtimeType} is async.',
      );
    }
    //
    // ignore: discarded_futures
    _onChanged(value);
  }

  Future<void> onChangedAsync(covariant T value) async {
    if (_ifActionIsSync(_onChanged)) {
      throw Exception(
        "Can't onChangedAsync(${value.runtimeType}) "
        'because ${value.runtimeType} is async.',
      );
    }

    await _onChanged(value);
  }

  @override
  List<Object?> get props => [enabled];
}

bool _ifActionIsSync<T>(FutureOr Function(T) action) {
  //
  /// Note: action MUST check that it's NOT Future<void> Function(),
  /// because checking if it's void Function() doesn't work.
  final isSync = action is! Future<void> Function();

  return isSync;
}

final class ValueChangedVm<T> extends BaseValueChangedVm<T> {
  ValueChangedVm({
    required this.value,
    super.onChanged,
    super.enabled,
  });

  final T value;

  @override
  List<Object?> get props => [...super.props, value];
}

final class ValueChangedWithItemsVm<T> extends BaseValueChangedVm<T> {
  ValueChangedWithItemsVm({
    super.onChanged,
    super.enabled = true,
    this.value,
    this.items = const [],
  });

  final T? value;
  final List<T> items;

  @override
  List<Object?> get props => [...super.props, ...items, value];
}

final class ValueChangedWithErrorVm<T> extends BaseValueChangedVm<T> {
  ValueChangedWithErrorVm({
    required this.value,
    super.onChanged,
    super.enabled = true,
    this.error,
  });

  final T value;
  final String? error;

  bool get isError => error != null;

  @override
  List<Object?> get props => [...super.props, error, value];
}
