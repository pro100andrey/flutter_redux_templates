import 'package:flutter/material.dart';
import 'package:localization/export.dart';

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
  });

  final bool isWaiting;
  final ValueChangedWithErrorVm<String, EmailErrorVm> email;
  final ValueChangedWithErrorVm<String, PasswordErrorVm> password;
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
                Assets.images.icLogo.svg(
                  height: 100,
                ),
                EmailInput(vm: vm.email),
                PasswordInput(vm: vm.password),
              ],
            )
          ],
        ),
      );
}
