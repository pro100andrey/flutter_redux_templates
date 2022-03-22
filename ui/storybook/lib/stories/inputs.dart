import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';
import 'package:ui/inputs/email_input.dart';
import 'package:ui/inputs/password_input.dart';

import 'inputs_vm_knobs.dart';

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
    ];


