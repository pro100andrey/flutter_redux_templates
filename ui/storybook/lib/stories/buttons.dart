import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';
import 'package:ui/buttons/form_button.dart';

import 'buttons_vm_knobs.dart';

List<Story> get buttons => [
      Story(
        name: 'Buttons/StyledButton',
        builder: (context) => Center(
          child: StyledButton(
            vm: context.newStyledButtonVm,
          ),
        ),
      ),
    ];


