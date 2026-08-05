import 'package:flutter/widgets.dart';

import '../../buttons/language_switcher.dart';
import '../../models/value_changed.dart';
import '../../theme/preview.dart';

void _ignore(String _) {}

@AppPreview(name: 'english selected', group: 'LanguageSwitcher')
Widget languageSwitcherPreview() => const LanguageSwitcher(
  vm: FieldVm<String>(value: 'en', onChanged: _ignore),
);

@AppPreview(name: 'ukrainian selected', group: 'LanguageSwitcher')
Widget languageSwitcherUkPreview() => const LanguageSwitcher(
  vm: FieldVm<String>(value: 'uk', onChanged: _ignore),
);

/// Disabled: the labels dim and the tap handler is dropped.
@AppPreview(name: 'disabled', group: 'LanguageSwitcher')
Widget languageSwitcherDisabledPreview() => const LanguageSwitcher(
  vm: FieldVm<String>(value: 'en', onChanged: _ignore, enabled: false),
);

/// A code with no segment — the case the widget's doc warns about, kept as a
/// preview so it is recognisable when it happens: nothing reads as selected.
@AppPreview(name: 'unknown locale', group: 'LanguageSwitcher')
Widget languageSwitcherUnknownPreview() => const LanguageSwitcher(
  vm: FieldVm<String>(value: 'de', onChanged: _ignore),
);
