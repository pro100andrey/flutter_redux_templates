import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../models/value_changed.dart';
import 'text_input.dart';

class PasswordInput extends StatelessWidget {
  const PasswordInput({
    required this.vm,
    Key? key,
  }) : super(key: key);

  final ValueChangedWithErrorVm<String> vm;

  @override
  Widget build(BuildContext context) => TextInput(
        vm: vm,
        labelText: S.current.password,
        prefixIcon: const Icon(Icons.password_outlined),
        keyboardType: TextInputType.visiblePassword,
        obscureText: true,
        autofillHints: const [AutofillHints.password],
      );
}
