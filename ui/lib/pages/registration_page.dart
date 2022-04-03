import 'package:flutter/material.dart';
import 'package:localization/export.dart';

import '../buttons/rounded_button.dart';
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
    required this.onPressedRegister,
  });

  final bool isWaiting;
  final ValueChangedWithErrorVm<String> email;
  final ValueChangedWithErrorVm<String> password;
  final ValueChangedWithErrorVm<String> confirmPassword;
  final VoidCallback? onPressedRegister;
}

class RegistrationPage extends StatelessWidget {
  const RegistrationPage({
    required this.vm,
    Key? key,
  }) : super(key: key);

  final RegistrationPageVm vm;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  Assets.placeholders.signUp.svg(height: 180),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: 320,
                    child: Column(
                      children: [
                        Text(
                          S.current.logIn,
                          style: Theme.of(context).textTheme.headline5,
                        ),
                        EmailInput(vm: vm.email),
                        PasswordInput(vm: vm.password),
                        ConfirmPasswordInput(vm: vm.confirmPassword),
                        const SizedBox(height: 16),
                        RoundedButton(
                          vm: RoundedButtonVm(
                            title: S.current.register,
                            onPressed: vm.onPressedRegister,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      );
}
