import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class ValuesChangedVm<T> extends Equatable {
  const ValuesChangedVm({
    this.onChanged = print,
    this.values = const [],
    this.items = const [],
    this.enabled = true,
  });

  final bool enabled;
  final List<T> values;
  final List<T> items;
  final ValueChanged<List<T>> onChanged;

  @override
  List<Object?> get props => [values, items, enabled];
}

void printD(Object? v) => print;

class ValueChangedVm<T> extends Equatable {
  const ValueChangedVm({
    this.onChanged = printD,
    this.value,
    this.enabled = true,
  });

  final bool enabled;
  final T? value;
  final FutureOr Function(T) onChanged;

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
  List<Object?> get props => [value, enabled];
}

bool _ifActionIsSync<T>(FutureOr Function(T) action) {
  //
  /// Note: action MUST check that it's NOT Future<void> Function(),
  /// because checking if it's void Function() doesn't work.
  final isSync = action is! Future<void> Function();

  return isSync;
}

class ValueChangedWithItemsVm<T> extends ValueChangedVm<T> {
  const ValueChangedWithItemsVm({
    super.onChanged,
    super.value,
    this.items = const [],
    super.enabled = true,
  });

  final List<T> items;

  @override
  List<Object?> get props => super.props + items;
}

class ValueChangedWithErrorVm<T> extends ValueChangedVm<T> {
  const ValueChangedWithErrorVm({
    super.onChanged,
    super.value,
    this.error,
    super.enabled = true,
  });

  final String? error;

  bool get isError => error != null;

  @override
  List<Object?> get props => super.props + [error];
}
