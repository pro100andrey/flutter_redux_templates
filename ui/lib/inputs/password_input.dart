import 'package:flutter/material.dart';
import 'package:localization/export.dart';

import '../models/value_changed.dart';
import 'base_input.dart';

enum PasswordErrorVm {
  isNotSet,
  isValid,
  isInvalid,
}

extension PasswordErrorVmExt on PasswordErrorVm {
  bool get isError =>
      this != PasswordErrorVm.isValid && this != PasswordErrorVm.isNotSet;

  bool get isValid => this == PasswordErrorVm.isValid;

  String? get localization {
    switch (this) {
      case PasswordErrorVm.isNotSet:
      case PasswordErrorVm.isValid:
        return null;
      case PasswordErrorVm.isInvalid:
        return S.current.emailInvalid;
    }
  }
}

class PasswordInput extends StatefulWidget {
  const PasswordInput({
    required this.vm,
    this.labelText,
    this.hintText,
    this.autofillHints,
    Key? key,
  }) : super(key: key);

  final ValueChangedWithErrorVm<String, PasswordErrorVm> vm;
  final String? labelText;
  final String? hintText;
  final List<String>? autofillHints;

  @override
  _PasswordInputState createState() => _PasswordInputState();
}

class _PasswordInputState extends State<PasswordInput> with BaseInput {
  @override
  Widget build(BuildContext context) => TextField(
        style: Theme.of(context).textTheme.bodyText1,
        controller: controller,
        keyboardType: TextInputType.emailAddress,
        autofillHints: widget.autofillHints,
        decoration: InputDecoration(
          enabled: widget.vm.onChanged != null,
          labelText: widget.labelText ?? S.current.password,
          hintText: widget.hintText,
          suffixIcon: widget.vm.error.isError ? const Icon(Icons.error) : null,
          errorText: widget.vm.error.localization,
        ),
      );

  @override
  ValueChanged<String>? get onUpdate => widget.vm.onChanged;

  @override
  String? get value => widget.vm.value;
}
