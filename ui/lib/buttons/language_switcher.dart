import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

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
/// **Which locales exist is not this widget's fact.** The segments come from
/// `S.delegate.supportedLocales` — generated from the ARB files, and what
/// `MaterialApp` already reads — so adding `intl_de.arb` puts German on the
/// control rather than making this the one place in the app that has not heard
/// of it. Only the endonym is not derivable, and that is all [_endonyms] holds.
///
/// **A locale is a bare language code here**, because that is what the app
/// models: `language.locale` is a `String`, and `MaterialApp` turns it back
/// with `Locale(vm.locale)`, which takes one subtag. Two region-qualified ARBs
/// for one language — `pt_BR` and `pt_PT` — therefore collapse to one segment
/// rather than two that both say `pt`; widening that is a change to the state
/// field and the `MaterialApp` line, not to this control.
///
/// Two segments because the app ships two locales. Past four or five a
/// segmented control is the wrong shape and a list is the right one.
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({required this.vm, super.key});

  final FieldVm<String> vm;

  /// Locale code to the name that language calls itself.
  ///
  /// A locale missing from here still gets a segment — its code, upper-cased —
  /// because an unlabelled option a user can still pick beats an option that
  /// silently is not there.
  static const _endonyms = <String, String>{
    'en': 'English',
    'uk': 'Українська',
  };

  @override
  Widget build(BuildContext context) => SegmentedControl<String>(
    vm: vm,
    segments: [
      for (final code in _codes)
        Segment(value: code, label: _endonyms[code] ?? code.toUpperCase()),
    ],
  );

  /// The supported language codes, in order, without repeats.
  ///
  /// Two segments holding the same value would both read as selected and
  /// dispatch the same action, which is worse than one — see the class doc for
  /// why the region subtag is dropped rather than carried.
  static List<String> get _codes {
    final seen = <String>{};
    return [
      for (final locale in S.delegate.supportedLocales)
        if (seen.add(locale.languageCode)) locale.languageCode,
    ];
  }
}
