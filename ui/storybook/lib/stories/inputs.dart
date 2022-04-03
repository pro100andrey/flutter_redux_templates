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
            vm: context.newEmailInputVm(),
          ),
        ),
      ),
      Story(
        name: 'Inputs/Password',
        builder: (context) => Center(
          child: PasswordInput(
            vm: context.newPasswordInputVm(),
          ),
        ),
      ),
      Story(
        name: 'Inputs/ConfirmPassword',
        builder: (context) => Center(
          child: ConfirmPasswordInput(
            vm: context.newPasswordInputVm(),
          ),
        ),
      ),
    ];

extension ButtonsKnobsBuildContextEx on BuildContext {
  ValueChangedWithErrorVm<String> newEmailInputVm() => ValueChangedWithErrorVm(
        value: null,
        error: knobInputError('Email error'),
        onChanged: knobOnValueChanged(label: 'Email onChanged'),
      );

  ValueChangedWithErrorVm<String> newPasswordInputVm() =>
      ValueChangedWithErrorVm(
        value: null,
        error: knobInputError('Password error'),
        onChanged: knobOnValueChanged(label: 'Password onChanged'),
      );
}
