import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

/// View-model for a form field: the current [value], a fire-and-forget
/// [onChanged], an optional [validator] (the form runs it on submit), and an
/// optional [error] for server/async errors injected onto the field.
///
/// [onChanged] and [validator] are excluded from [props] — they are behavior,
/// not display, and are fresh closures each build; including them would break
/// VM equality and cause the connector to rebuild on every dispatch.
final class FieldVm<T> extends Equatable {
  const FieldVm({
    required this.value,
    required this.onChanged,
    this.validator,
    this.error,
    this.enabled = true,
  });

  final T value;
  // T in a callback param is contravariant; safe here — the VM is built and
  // passed through, never stored covariantly.
  // ignore: unsafe_variance
  final ValueChanged<T> onChanged;
  // Same as onChanged: contravariant T in a callback param, safe here.
  // ignore: unsafe_variance
  final FormFieldValidator<T>? validator;

  /// Server/async error shown on the field (via `forceErrorText`). Format
  /// validation stays in [validator].
  final String? error;
  final bool enabled;

  @override
  List<Object?> get props => [value, error, enabled];
}

/// One option in a [ChoiceVm].
///
/// [label] is data, not design: it is resolved where the locale and the domain
/// live — the connector — so `ui` never reaches for either.
final class ChoiceItemVm<T> extends Equatable {
  const ChoiceItemVm({required this.value, required this.label});

  final T value;
  final String label;

  @override
  List<Object?> get props => [value, label];
}

/// View-model for a field whose value is picked from a finite set.
///
/// Same contract as [FieldVm], plus the [items] to pick from. Use it when the
/// set is data (loaded, localized, user-specific); when the set is fixed by
/// design, the widget declares it instead — see `SegmentedControl.segments`.
///
/// [value] must be one of [items]; anything else renders as "nothing selected".
final class ChoiceVm<T> extends Equatable {
  const ChoiceVm({
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.error,
    this.enabled = true,
  });

  final T value;
  final List<ChoiceItemVm<T>> items;
  // Contravariant T in a callback param, safe here — same as FieldVm.
  // ignore: unsafe_variance
  final ValueChanged<T> onChanged;
  // Same as onChanged.
  // ignore: unsafe_variance
  final FormFieldValidator<T>? validator;
  final String? error;
  final bool enabled;

  @override
  List<Object?> get props => [value, items, error, enabled];
}
