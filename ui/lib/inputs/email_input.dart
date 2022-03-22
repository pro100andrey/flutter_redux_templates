import 'package:flutter/material.dart';
import 'package:localization/export.dart';

import '../models/value_changed.dart';
import 'base_input.dart';

enum EmailErrorVm {
  isNotSet,
  isValid,
  isInvalid,
}

extension EmailErrorVmExt on EmailErrorVm {
  bool get isError =>
      this != EmailErrorVm.isValid && this != EmailErrorVm.isNotSet;

  bool get isValid => this == EmailErrorVm.isValid;

  String? get localization {
    switch (this) {
      case EmailErrorVm.isNotSet:
      case EmailErrorVm.isValid:
        return null;
      case EmailErrorVm.isInvalid:
        return S.current.emailInvalid;
    }
  }
}

class EmailInput extends StatefulWidget {
  const EmailInput({
    required this.vm,
    this.labelText,
    this.hintText,
    this.autofillHints,
    Key? key,
  }) : super(key: key);

  final ValueChangedWithErrorVm<String, EmailErrorVm> vm;

  final String? labelText;
  final String? hintText;
  final List<String>? autofillHints;

  @override
  _EmailInputState createState() => _EmailInputState();
}

class _EmailInputState extends State<EmailInput> with BaseInput {
  @override
  Widget build(BuildContext context) => TextField(
        style: Theme.of(context).textTheme.bodyText1,
        controller: controller,
        keyboardType: TextInputType.emailAddress,
        autofillHints: widget.autofillHints,
        decoration: InputDecoration(
          enabled: widget.vm.onChanged != null,
          labelText: widget.labelText ?? S.current.email,
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
