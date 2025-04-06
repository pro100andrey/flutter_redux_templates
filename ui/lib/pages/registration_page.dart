import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../buttons/styled_elevated_button.dart';
import '../containers/auth_from_container.dart';
import '../inputs/confirm_password_input.dart';
import '../inputs/email_input.dart';
import '../inputs/password_input.dart';
import '../models/value_changed.dart';

class RegistrationPage extends StatelessWidget {
  const RegistrationPage({
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.onPressedRegister,
    required this.onPressedBackToLogin,
    super.key,
  });

  final ValueChangedWithErrorVm<String?> email;
  final ValueChangedWithErrorVm<String?> password;
  final ValueChangedWithErrorVm<String?> confirmPassword;
  final VoidCallback? onPressedRegister;
  final VoidCallback? onPressedBackToLogin;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        AuthFormContainer(
          title: S.current.register,
          children: [
            const SizedBox(height: 24),
            EmailInput(vm: email),
            const SizedBox(height: 16),
            PasswordInput(vm: password),
            const SizedBox(height: 16),
            ConfirmPasswordInput(vm: confirmPassword),
            const SizedBox(height: 16),
            StyledElevatedButton(
              title: S.current.register,
              onPressed: onPressedRegister,
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
