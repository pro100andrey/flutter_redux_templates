import 'package:flutter/material.dart';

import '../models/value_changed.dart';
import '../theme/common.dart';

/// Thin text input over [TextFormField], driven by a [FieldVm].
///
/// - Validation is native: [FieldVm.validator] runs on `Form.validate()`.
/// - Server/async errors are injected via [FieldVm.error] → `forceErrorText`.
/// - Empty text is normalized to `null` before [FieldVm.onChanged].
///
/// Uncontrolled: [FieldVm.value] seeds the field once and is not synced back.
/// A reducer that resets the substate while the field stays mounted leaves the
/// text stale against a null store. Swap in a controller if you do that.
class InputFormField extends StatelessWidget {
  const InputFormField({
    required this.vm,
    this.labelText,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.autofillHints,
    this.obscureText = false,
    this.focusNode,
    this.textInputAction,
    this.onFieldSubmitted,
    super.key,
  });

  final FieldVm<String?> vm;
  final String? labelText;
  final String? hintText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final List<String>? autofillHints;
  final bool obscureText;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextFormField(
      initialValue: vm.value,
      focusNode: focusNode,
      textInputAction: textInputAction,
      enabled: vm.enabled,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      obscureText: obscureText,
      validator: vm.validator,
      forceErrorText: vm.error,
      // Resolved here, not left to `ThemeData`: `ThemeData.lerp` swaps
      // `inputDecorationTheme` at t=0.5 instead of interpolating it, which
      // makes the border flash on a theme switch.
      decoration:
          InputDecoration(
            labelText: labelText,
            hintText: hintText,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
          ).applyDefaults(
            inputDecorationThemeFrom(
              theme.inputDecorationTheme,
              theme.colorScheme,
            ),
          ),
      onChanged: (value) => vm.onChanged(value.isEmpty ? null : value),
      onFieldSubmitted: onFieldSubmitted,
    );
  }
}
