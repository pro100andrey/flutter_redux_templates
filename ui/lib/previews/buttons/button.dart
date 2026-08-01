import 'package:flutter/widgets.dart';

import '../../buttons/button.dart';
import '../../theme/preview.dart';

@AppPreview(name: 'primary', group: 'Button')
Widget buttonPrimaryPreview() =>
    Button.primary(label: 'Primary', onPressed: () {});

@AppPreview(name: 'secondary', group: 'Button')
Widget buttonSecondaryPreview() =>
    Button.secondary(label: 'Secondary', onPressed: () {});

@AppPreview(name: 'text', group: 'Button')
Widget buttonTextPreview() => Button.text(label: 'Text', onPressed: () {});

@AppPreview(name: 'danger', group: 'Button')
Widget buttonDangerPreview() =>
    Button.danger(label: 'Danger', onPressed: () {});

/// Null `onPressed` is the disabled state — there is no `enabled` flag.
@AppPreview(name: 'disabled', group: 'Button')
Widget buttonDisabledPreview() =>
    const Button.primary(label: 'Disabled', onPressed: null);
