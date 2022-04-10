import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../models/value_changed.dart';
import 'text_input.dart';

class ConfirmPasswordInput extends StatelessWidget {
  const ConfirmPasswordInput({
    required this.vm,
    Key? key,
  }) : super(key: key);

  final ValueChangedWithErrorVm<String> vm;

  @override
  Widget build(BuildContext context) => TextInput(
        vm: vm,
        labelText: S.current.confirmPassword,
        prefixIcon: const Icon(Icons.check_outlined),
        keyboardType: TextInputType.visiblePassword,
        obscureText: true,
      );
}
