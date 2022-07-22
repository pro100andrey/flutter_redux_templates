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

  @override
  List<Object?> get props => [value, enabled];
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
