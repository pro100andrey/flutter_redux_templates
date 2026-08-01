import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../buttons/button.dart';
import '../containers/auth_from_container.dart';
import '../forms/base_form.dart';
import '../inputs/confirm_password_form_field.dart';
import '../inputs/password_form_field.dart';
import '../models/value_changed.dart';
import '../theme/spacing.dart';

class ResetPasswordPage extends StatelessWidget {
  const ResetPasswordPage({
    required this.password,
    required this.confirmPassword,
    required this.onPressedResetPassword,
    required this.onPressedBackToLogin,
    super.key,
  });

  final FieldVm<String?> password;
  final FieldVm<String?> confirmPassword;
  final VoidCallback onPressedResetPassword;
  final VoidCallback onPressedBackToLogin;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: BaseForm(
      builder: (context, form) => AuthFormContainer(
        title: S.current.resetPassword,
        children: [
          Gaps.lg,
          PasswordFormField(vm: password),
          Gaps.md,
          ConfirmPasswordFormField(vm: confirmPassword),
          Gaps.md,
          Button.primary(
            label: S.current.resetPassword,
            onPressed: () {
              if (form.validateAndSave()) {
                onPressedResetPassword();
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
