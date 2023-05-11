import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../indicators/base_circle_indicator.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({
    super.key,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(S.current.title),
        ),
        body: const BaseCircleIndicator(),
      );
}
