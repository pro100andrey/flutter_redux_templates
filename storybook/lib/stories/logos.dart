import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';
import 'package:ui/logo/logo.dart';

List<Story> get logos => [
      Story(
        name: 'Logos/Base',
        builder: (context) => const Center(
          child: Logo(),
        ),
      ),
    ];
