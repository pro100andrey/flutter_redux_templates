import 'package:flutter/material.dart';

import '../models/value_changed.dart';
import 'segmented_control.dart';
import 'theme_switcher.dart';

/// Locale switcher, shaped after [ThemeSwitcher] because it is the same thing:
/// a fixed set, one selected, a tap reports through [FieldVm.onChanged].
///
/// The value is the locale code the app state holds — `en`, `uk` — not a
/// `Locale`. `business` must not name a Flutter type to say which language is
/// selected; `MaterialApp` turns the code back into a `Locale` at the top.
///
/// **The labels are endonyms, and deliberately not translated.** "Українська"
/// stays Ukrainian in an English UI, because the person reaching for this
/// control is the one who cannot read the language currently on screen. Running
/// them through `S.current` would hide each option from exactly the user
/// looking for it — which is why they are constants here and not l10n keys.
///
/// Two segments because the app ships two locales. A third goes in [supported]
/// and in `intl_*.arb`; past four or five a segmented control is the wrong
/// shape and a list is the right one.
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({required this.vm, super.key});

  final FieldVm<String> vm;

  /// Locale code to the name that language calls itself. Keep in step with
  /// `S.delegate.supportedLocales`.
  static const supported = <String, String>{
    'en': 'English',
    'uk': 'Українська',
  };

  @override
  Widget build(BuildContext context) => SegmentedControl<String>(
    vm: vm,
    segments: [
      for (final entry in supported.entries)
        Segment(value: entry.key, label: entry.value),
    ],
  );
}
