import 'package:flutter/material.dart';

import '../models/value_changed.dart';
import '../theme/common.dart';

/// Dropdown over [DropdownButtonFormField], driven by a [ChoiceVm].
///
/// Shares the input decoration with `InputFormField`, so a form mixing text and
/// choice fields reads as one control set.
class ChoiceFormField<T> extends StatelessWidget {
  const ChoiceFormField({
    required this.vm,
    this.labelText,
    this.hintText,
    this.prefixIcon,
    super.key,
  });

  final ChoiceVm<T> vm;
  final String? labelText;
  final String? hintText;
  final Widget? prefixIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropdownButtonFormField<T>(
      initialValue: vm.value,
      validator: vm.validator,
      forceErrorText: vm.error,
      decoration:
          InputDecoration(
            labelText: labelText,
            hintText: hintText,
            prefixIcon: prefixIcon,
          ).applyDefaults(
            inputDecorationThemeFrom(
              theme.inputDecorationTheme,
              theme.colorScheme,
            ),
          ),
      items: [
        for (final item in vm.items)
          DropdownMenuItem(value: item.value, child: Text(item.label)),
      ],
      // Null arrives when the menu is dismissed without a pick.
      onChanged: vm.enabled
          ? (value) {
              if (value != null) {
                vm.onChanged(value);
              }
            }
          : null,
    );
  }
}
