import 'package:flutter/material.dart';

import '../indicators/base_circle_indicator.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({
    super.key,
  });

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: BaseCircleIndicator(),
      );
}
