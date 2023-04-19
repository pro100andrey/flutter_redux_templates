import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';
import 'package:ui/generated/assets.gen.dart';

List<Story> get logos => [
      Story(
        name: 'Logos/Base',
        builder: (context) => Center(
          child: Assets.placeholders.image.svg(),
        ),
      ),
    ];
