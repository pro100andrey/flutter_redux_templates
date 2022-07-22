import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import '../assets.dart';

import '../buttons/rounded_button.dart';
import '../containers/auth_from_container.dart';
import '../inputs/confirm_password_input.dart';
import '../inputs/password_input.dart';
import '../models/value_changed.dart';

class ResetPasswordPage extends StatelessWidget {
  const ResetPasswordPage({
    required this.password,
    required this.confirmPassword,
    required this.onPressedResetPassword,
    required this.onPressedBackToLogin,
    super.key,
  });

  final ValueChangedWithErrorVm<String> password;
  final ValueChangedWithErrorVm<String> confirmPassword;
  final VoidCallback? onPressedResetPassword;
  final VoidCallback? onPressedBackToLogin;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            AuthFormContainer(
              placeholder: Assets.placeholders.image,
              title: S.current.resetPassword,
              children: [
                const SizedBox(height: 24),
                PasswordInput(vm: password),
                const SizedBox(height: 16),
                ConfirmPasswordInput(vm: confirmPassword),
                const SizedBox(height: 16),
                RoundedButton(
                  title: S.current.resetPassword,
                  onPressed: onPressedResetPassword,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: onPressedBackToLogin,
                  child: Text(S.current.backToLogIn),
                ),
              ],
            ),
          ],
        ),
      );
}
