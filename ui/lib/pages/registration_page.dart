import 'package:flutter/material.dart';
import 'package:localization/export.dart';

import '../generated/assets.gen.dart';
import '../inputs/confirm_password_input.dart';
import '../inputs/email_input.dart';
import '../inputs/password_input.dart';
import '../models/value_changed.dart';

@immutable
class RegistrationPageVm {
  const RegistrationPageVm({
    required this.isWaiting,
    required this.email,
    required this.password,
    required this.confirmPassword,
  });

  final bool isWaiting;
  final ValueChangedWithErrorVm<String> email;
  final ValueChangedWithErrorVm<String> password;
  final ValueChangedWithErrorVm<String> confirmPassword;
}

class RegistrationPage extends StatelessWidget {
  const RegistrationPage({
    required this.vm,
    Key? key,
  }) : super(key: key);

  final RegistrationPageVm vm;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(S.current.registration)),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Assets.images.icLogo.svg(height: 100),
                EmailInput(vm: vm.email),
                PasswordInput(vm: vm.password),
                ConfirmPasswordInput(vm: vm.confirmPassword),
              ],
            )
          ],
        ),
      );
}
