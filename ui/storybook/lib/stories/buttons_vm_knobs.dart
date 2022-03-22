import 'package:flutter/material.dart';
import 'package:ui/buttons/form_button.dart';

import 'knobs.dart';

extension ButtonsKnobsBuildContextEx on BuildContext {
  StyledButtonVm get newStyledButtonVm => StyledButtonVm(
        onPressed: knobOnPressed(),
        title: knobWords(label: 'Title'),
      );
}
