import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({
    super.key,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(S.current.title),
        ),
        body: Stack(
          children: const [
            Center(
              child: Text('SplashPage'),
            ),
          ],
        ),
      );
}
