import 'package:flutter/material.dart';

import '../assets.dart';

class Logo extends StatelessWidget {
  const Logo({
    super.key,
  });

  @override
  Widget build(BuildContext context) => Assets.placeholders.image.svg();
}
