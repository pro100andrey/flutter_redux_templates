import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({
    required this.isWaiting,
    Key? key,
  }) : super(key: key);

  final bool isWaiting;

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
