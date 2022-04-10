import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../models/value_changed.dart';
import 'text_input.dart';

class EmailInput extends StatelessWidget {
  const EmailInput({
    required this.vm,
    Key? key,
  }) : super(key: key);

  final ValueChangedWithErrorVm<String> vm;

  @override
  Widget build(BuildContext context) => TextInput(
        vm: vm,
        labelText: S.current.email,
        prefixIcon: const Icon(Icons.email_outlined),
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
      );
}
