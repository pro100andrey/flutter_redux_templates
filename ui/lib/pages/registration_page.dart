import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../buttons/button.dart';
import '../containers/auth_from_container.dart';
import '../forms/base_form.dart';
import '../inputs/confirm_password_form_field.dart';
import '../inputs/email_form_field.dart';
import '../inputs/password_form_field.dart';
import '../models/value_changed.dart';
import '../theme/spacing.dart';

class RegistrationPage extends StatelessWidget {
  const RegistrationPage({
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.onPressedRegister,
    required this.onPressedBackToLogin,
    super.key,
  });

  final FieldVm<String?> email;
  final FieldVm<String?> password;
  final FieldVm<String?> confirmPassword;
  final VoidCallback onPressedRegister;
  final VoidCallback onPressedBackToLogin;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: BaseForm(
      builder: (context, form) => AuthFormContainer(
        title: S.current.register,
        children: [
          Gaps.lg,
          EmailFormField(vm: email),
          Gaps.md,
          PasswordFormField(vm: password),
          Gaps.md,
          ConfirmPasswordFormField(vm: confirmPassword),
          Gaps.md,
          Button.primary(
            label: S.current.register,
            onPressed: () {
              if (form.validateAndSave()) {
                onPressedRegister();
              }
            },
          ),
          Gaps.md,
          Button.text(
            label: S.current.backToLogIn,
            onPressed: onPressedBackToLogin,
          ),
        ],
      ),
    ),
  );
}
