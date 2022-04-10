import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';
import 'package:ui/buttons/rounded_button.dart';

import 'knobs.dart';

List<Story> get buttons => [
      Story(
        name: 'Buttons/RoundedButton',
        builder: (context) => Center(
          child: RoundedButton(
            title: context.knobs.text(
              label: 'Rounded button',
              initial: 'Button',
            ),
            onPressed: context.knobOnPressedOptional(),
          ),
        ),
      ),
      Story(
        name: 'Buttons/TextButton',
        builder: (context) => Center(
          child: TextButton(
            onPressed: context.knobOnPressedOptional(),
            child: Text(
              context.knobs.text(label: 'Text button', initial: 'Button'),
            ),
          ),
        ),
      ),
    ];
