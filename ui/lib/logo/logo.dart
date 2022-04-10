import 'package:flutter/material.dart';

import '../assets.dart';

class Logo extends StatelessWidget {
  const Logo({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => Assets.images.icLogo.svg();
}
