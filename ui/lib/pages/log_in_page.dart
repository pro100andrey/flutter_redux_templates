import 'package:flutter/material.dart';
import 'package:localization/export.dart';

import '../buttons/rounded_button.dart';
import '../export.dart';
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
  });

  final bool isWaiting;
  final ValueChangedWithErrorVm<String> email;
  final ValueChangedWithErrorVm<String> password;
  final VoidCallback? onPressedLogIn;
}

class LogInPage extends StatelessWidget {
  const LogInPage({
    required this.vm,
    Key? key,
  }) : super(key: key);

  final LogInPageVm vm;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(S.current.logIn)),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 32),
                Assets.images.icLogo.svg(height: 100),
                const SizedBox(height: 16),
                EmailInput(vm: vm.email),
                const SizedBox(height: 16),
                PasswordInput(vm: vm.password),
                const SizedBox(height: 32),
                
                Center(
                  child: RoundedButton(
                    vm: RoundedButtonVm(
                      title: S.current.logIn,
                      onPressed: vm.onPressedLogIn,
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      );
}
