import 'dart:async';

import 'package:equatable/equatable.dart';

void printD(Object? v) => print;

typedef VoidCallbackVm = FutureOr Function();

class BaseValueChangedVm<T> extends Equatable {
  const BaseValueChangedVm({this.onChanged = printD, this.enabled = true});

  final bool enabled;
  final FutureOr Function(T value) onChanged;

  void onChangedSync(T value) {
    if (!_ifActionIsSync(onChanged)) {
      throw Exception(
        "Can't onChangedSync(${value.runtimeType}) "
        'because ${value.runtimeType} is async.',
      );
    }

    // ignore: discarded_futures
    onChanged(value);
  }

  Future<void> onChangedAsync(T value) async {
    if (_ifActionIsSync(onChanged)) {
      throw Exception(
        "Can't onChangedAsync(${value.runtimeType}) "
        'because ${value.runtimeType} is async.',
      );
    }

    await onChanged(value);
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

class ValueChangedVm<T> extends BaseValueChangedVm<T> {
  const ValueChangedVm({
    required this.value,
    super.onChanged = printD,
    super.enabled,
  });

  final T value;

  @override
  List<Object?> get props => [value, enabled];
}

class ValueChangedWithItemsVm<T> extends BaseValueChangedVm<T> {
  const ValueChangedWithItemsVm({
    super.onChanged,
    super.enabled = true,
    this.value,
    this.items = const [],
  });

  final T? value;
  final List<T> items;

  @override
  List<Object?> get props => super.props + items + [value];
}

class ValueChangedWithErrorVm<T> extends BaseValueChangedVm<T> {
  const ValueChangedWithErrorVm({
    required this.value,
    super.onChanged,
    super.enabled = true,
    this.error,
  });

  final T value;
  final String? error;

  bool get isError => error != null;

  @override
  List<Object?> get props => super.props + [error, value];
}
