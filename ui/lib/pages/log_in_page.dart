import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../buttons/button.dart';
import '../buttons/theme_switcher.dart';
import '../containers/auth_from_container.dart';
import '../forms/base_form.dart';
import '../inputs/email_form_field.dart';
import '../inputs/password_form_field.dart';
import '../models/value_changed.dart';
import '../theme/spacing.dart';

class LogInPage extends StatelessWidget {
  const LogInPage({
    required this.email,
    required this.password,
    required this.onPressedLogIn,
    required this.onPressedForgotPassword,
    required this.onPressedRegister,
    required this.theme,
    super.key,
  });

  final FieldVm<String?> email;
  final FieldVm<String?> password;
  final VoidCallback onPressedLogIn;
  final VoidCallback onPressedForgotPassword;
  final VoidCallback onPressedRegister;
  final FieldVm<ThemeMode> theme;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: BaseForm(
      builder: (context, form) => AuthFormContainer(
        title: S.current.logIn,
        subtitle: S.current.logInSubtitle,
        trailing: ThemeSwitcher(vm: theme),
        children: [
          Gaps.lg,
          EmailFormField(vm: email),
          Gaps.md,
          PasswordFormField(vm: password),
          Gaps.md,
          Align(
            alignment: Alignment.centerRight,
            child: Button.text(
              label: S.current.forgotPassword,
              onPressed: onPressedForgotPassword,
            ),
          ),
          Gaps.md,
          Button.primary(
            label: S.current.logIn,
            onPressed: () {
              if (form.validateAndSave()) {
                onPressedLogIn();
              }
            },
          ),
          Gaps.md,
          Button.secondary(
            label: S.current.register,
            onPressed: onPressedRegister,
          ),
        ],
      ),
    ),
  );
}
