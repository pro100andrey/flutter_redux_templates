import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import 'text_input.dart';

class ConfirmPasswordInput extends BaseTextInput {
  ConfirmPasswordInput({
    required super.vm,
    super.key,
  }) : super(
          labelText: S.current.confirmPassword,
          prefixIcon: const Icon(Icons.check_outlined),
          keyboardType: TextInputType.visiblePassword,
          obscureText: true,
        );
}
