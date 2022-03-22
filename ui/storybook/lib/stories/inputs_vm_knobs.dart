import 'package:flutter/material.dart';
import 'package:ui/inputs/email_input.dart';
import 'package:ui/inputs/password_input.dart';
import 'package:ui/models/value_changed.dart';

import 'knobs.dart';

extension ButtonsKnobsBuildContextEx on BuildContext {
  ValueChangedWithErrorVm<String, EmailErrorVm> newEmailInputVm() =>
      ValueChangedWithErrorVm(
        value: null,
        error: EmailErrorVm.isValid,
        onChanged: knobOnValueChanged,
      );

  ValueChangedWithErrorVm<String, PasswordErrorVm> newPasswordInputVm() =>
      ValueChangedWithErrorVm(
        value: null,
        error: PasswordErrorVm.isValid,
        onChanged: knobOnValueChanged,
      );
}
