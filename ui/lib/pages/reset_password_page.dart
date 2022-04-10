import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

@immutable
class ResetPasswordPageVm {
  const ResetPasswordPageVm({
    required this.isWaiting,
  });
  final bool isWaiting;
}

class ResetPasswordPage extends StatelessWidget {
  const ResetPasswordPage({
    required this.vm,
    Key? key,
  }) : super(key: key);

  final ResetPasswordPageVm vm;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(S.current.title),
        ),
        body: Stack(
          children: const [
            Center(
              child: Text('ResetPasswordPage'),
            ),
          ],
        ),
      );
}
