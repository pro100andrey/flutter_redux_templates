import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import 'base_text_input.dart';

class EmailInput extends BaseTextInput {
  EmailInput({
    required super.vm,
    super.key,
  }) : super(
          labelText: S.current.email,
          prefixIcon: const Icon(Icons.email_outlined),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
        );
}
