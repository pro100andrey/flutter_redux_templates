import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';
import 'package:ui/buttons/base_text_button.dart';
import 'package:ui/buttons/rounded_button.dart';

import 'knobs.dart';

List<Story> get buttons => [
      Story(
        name: 'Buttons/RoundedButton',
        builder: (context) => Center(
          child: RoundedButton(vm: context.newRoundedButtonVm()),
        ),
      ),
      Story(
        name: 'Buttons/TextButton',
        builder: (context) => Center(
          child: BaseTextButton(vm: context.newTextButtonVm()),
        ),
      ),
    ];

extension ButtonsKnobsBuildContextEx on BuildContext {
  RoundedButtonVm newRoundedButtonVm({String? label}) => RoundedButtonVm(
        onPressed: knobOnPressed(),
        title: knobs.text(label: label ?? 'Rounded button', initial: 'Button'),
      );

  BaseTextButtonVm newTextButtonVm({String? label}) => BaseTextButtonVm(
        onPressed: knobOnPressed(),
        title: knobs.text(label: label ?? 'Text button', initial: 'Button'),
      );
}
