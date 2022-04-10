import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../assets.dart';
import '../buttons/base_text_button.dart';
import '../buttons/rounded_button.dart';
import '../inputs/email_input.dart';
import '../inputs/password_input.dart';
import '../models/value_changed.dart';

@immutable
class LogInPageVm {
  const LogInPageVm({
    required this.isWaiting,
    required this.email,
    required this.password,
    required this.onPressedLogIn,
    required this.onPressedForgotPassword,
  });

  final bool isWaiting;
  final ValueChangedWithErrorVm<String> email;
  final ValueChangedWithErrorVm<String> password;
  final VoidCallback? onPressedLogIn;
  final VoidCallback? onPressedForgotPassword;
}

class LogInPage extends StatelessWidget {
  const LogInPage({
    required this.vm,
    Key? key,
  }) : super(key: key);

  final LogInPageVm vm;

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
                  Assets.placeholders.logIn.svg(height: 180),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: 320,
                    child: Column(
                      children: [
                        Text(
                          S.current.logIn,
                          style: Theme.of(context).textTheme.headline5,
                        ),
                        const SizedBox(height: 16),
                        EmailInput(vm: vm.email),
                        const SizedBox(height: 16),
                        PasswordInput(vm: vm.password),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            BaseTextButton(
                              vm: BaseTextButtonVm(
                                title: S.current.forgotPassword,
                                onPressed: vm.onPressedForgotPassword,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        RoundedButton(
                          vm: RoundedButtonVm(
                            title: S.current.logIn,
                            onPressed: vm.onPressedLogIn,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
