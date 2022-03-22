import 'package:flutter/material.dart';
import 'package:localization/export.dart';

@immutable
class ForgotPasswordPageVm {
  const ForgotPasswordPageVm({
    required this.isWaiting,
  });
  final bool isWaiting;
}

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({
    required this.vm,
    Key? key,
  }) : super(key: key);

  final ForgotPasswordPageVm vm;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(S.current.forgotPassword),
        ),
        body: Stack(
          children: [
            Center(
              child: Text(S.current.forgotPassword),
            ),
          ],
        ),
      );
}
