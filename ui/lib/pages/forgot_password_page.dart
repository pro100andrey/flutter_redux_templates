import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../buttons/button.dart';
import '../containers/auth_from_container.dart';
import '../forms/base_form.dart';
import '../inputs/email_form_field.dart';
import '../models/value_changed.dart';
import '../theme/spacing.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({
    required this.email,
    required this.onPressedResetPassword,
    required this.onPressedBackToLogin,
    super.key,
  });

  final FieldVm<String?> email;
  final VoidCallback onPressedResetPassword;
  final VoidCallback onPressedBackToLogin;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: BaseForm(
      builder: (context, form) => AuthFormContainer(
        title: S.current.forgotPassword,
        children: [
          Gaps.lg,
          EmailFormField(vm: email),
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
