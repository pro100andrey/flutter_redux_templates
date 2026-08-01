import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../models/value_changed.dart';
import 'input_form_field.dart';

/// Password input with a show/hide eye-toggle (the one bit of local state over
/// [InputFormField]).
class PasswordFormField extends StatefulWidget {
  const PasswordFormField({
    required this.vm,
    this.labelText,
    this.prefixIcon,
    this.textInputAction,
    this.onFieldSubmitted,
    super.key,
  });

  final FieldVm<String?> vm;
  final String? labelText;
  final Widget? prefixIcon;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  State<PasswordFormField> createState() => _PasswordFormFieldState();
}

class _PasswordFormFieldState extends State<PasswordFormField> {
  var _obscure = true;

  @override
  Widget build(BuildContext context) => InputFormField(
    vm: widget.vm,
    labelText: widget.labelText ?? S.current.password,
    prefixIcon: widget.prefixIcon ?? const Icon(Icons.lock_outline),
    keyboardType: TextInputType.visiblePassword,
    autofillHints: const [AutofillHints.password],
    obscureText: _obscure,
    textInputAction: widget.textInputAction,
    onFieldSubmitted: widget.onFieldSubmitted,
    suffixIcon: IconButton(
      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
      onPressed: () => setState(() => _obscure = !_obscure),
    ),
  );
}
