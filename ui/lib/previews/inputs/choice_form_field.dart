import 'package:flutter/widgets.dart';

import '../../inputs/choice_form_field.dart';
import '../../models/value_changed.dart';
import '../../theme/preview.dart';

const _items = [
  ChoiceItemVm(value: 'draft', label: 'Draft'),
  ChoiceItemVm(value: 'active', label: 'Active'),
  ChoiceItemVm(value: 'archived', label: 'Archived'),
];

@AppPreview(name: 'selected', group: 'ChoiceFormField')
Widget choiceSelectedPreview() => const ChoiceFormField<String?>(
  labelText: 'Tag',
  vm: ChoiceVm(value: 'active', items: _items, onChanged: _ignore),
);

/// A value outside [ChoiceVm.items] — the control reads as "nothing picked".
@AppPreview(name: 'empty', group: 'ChoiceFormField')
Widget choiceEmptyPreview() => const ChoiceFormField<String?>(
  labelText: 'Tag',
  vm: ChoiceVm(value: null, items: _items, onChanged: _ignore),
);

@AppPreview(name: 'error', group: 'ChoiceFormField')
Widget choiceErrorPreview() => const ChoiceFormField<String?>(
  labelText: 'Tag',
  vm: ChoiceVm(
    value: null,
    items: _items,
    error: 'Pick a tag',
    onChanged: _ignore,
  ),
);

@AppPreview(name: 'disabled', group: 'ChoiceFormField')
Widget choiceDisabledPreview() => const ChoiceFormField<String?>(
  labelText: 'Tag',
  vm: ChoiceVm(
    value: 'draft',
    items: _items,
    enabled: false,
    onChanged: _ignore,
  ),
);

void _ignore(String? _) {}
