import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import 'text_input.dart';

class PasswordInput extends BaseTextInput {
  PasswordInput({
    required super.vm,
    super.key,
  }) : super(
          labelText: S.current.password,
          prefixIcon: const Icon(Icons.password_outlined),
          keyboardType: TextInputType.visiblePassword,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
        );
}
