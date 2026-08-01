import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../models/value_changed.dart';
import 'password_form_field.dart';

class ConfirmPasswordFormField extends StatelessWidget {
  const ConfirmPasswordFormField({
    required this.vm,
    this.textInputAction,
    this.onFieldSubmitted,
    super.key,
  });

  final FieldVm<String?> vm;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) => PasswordFormField(
    vm: vm,
    labelText: S.current.confirmPassword,
    prefixIcon: const Icon(Icons.check),
    textInputAction: textInputAction,
    onFieldSubmitted: onFieldSubmitted,
  );
}
