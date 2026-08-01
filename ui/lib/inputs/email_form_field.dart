import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../models/value_changed.dart';
import 'input_form_field.dart';

class EmailFormField extends StatelessWidget {
  const EmailFormField({
    required this.vm,
    this.textInputAction,
    this.onFieldSubmitted,
    super.key,
  });

  final FieldVm<String?> vm;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) => InputFormField(
    vm: vm,
    labelText: S.current.email,
    prefixIcon: const Icon(Icons.email_outlined),
    keyboardType: TextInputType.emailAddress,
    autofillHints: const [AutofillHints.email],
    textInputAction: textInputAction,
    onFieldSubmitted: onFieldSubmitted,
  );
}
