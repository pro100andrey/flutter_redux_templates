import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';
import 'package:ui/inputs/confirm_password_input.dart';
import 'package:ui/inputs/email_input.dart';
import 'package:ui/inputs/password_input.dart';
import 'package:ui/models/value_changed.dart';

import 'knobs.dart';

List<Story> get inputs => [
      Story(
        name: 'Inputs/Email',
        builder: (context) => Center(
          child: EmailInput(
            vm: context.newInputVm('Email'),
          ),
        ),
      ),
      Story(
        name: 'Inputs/Password',
        builder: (context) => Center(
          child: PasswordInput(
            vm: context.newInputVm('Password'),
          ),
        ),
      ),
      Story(
        name: 'Inputs/ConfirmPassword',
        builder: (context) => Center(
          child: ConfirmPasswordInput(
            vm: context.newInputVm('ConfirmPassword'),
          ),
        ),
      ),
    ];

extension ButtonsKnobsBuildContextEx on BuildContext {
  StringCallback newInputVm(String label) => StringCallback(
        value: null,
        error: knobInputError('$label error'),
        onChanged: knobOnValueChanged(label: '$label onChanged'),
      );
}
