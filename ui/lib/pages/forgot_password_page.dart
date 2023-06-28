import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../buttons/rounded_button.dart';
import '../containers/auth_from_container.dart';
import '../generated/assets.gen.dart';
import '../inputs/email_input.dart';
import '../models/value_changed.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({
    required this.isWaiting,
    required this.email,
    required this.onPressedResetPassword,
    required this.onPressedBackToLogin,
    super.key,
  });

  final bool isWaiting;
  final ValueChangedWithErrorVm<String> email;
  final VoidCallback? onPressedResetPassword;
  final VoidCallback onPressedBackToLogin;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            AuthFormContainer(
              placeholder: Assets.placeholders.image,
              title: S.current.forgotPassword,
              children: [
                const SizedBox(height: 24),
                EmailInput(vm: email),
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
