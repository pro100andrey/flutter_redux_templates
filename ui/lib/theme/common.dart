/// How theming is organized in this project.
///
/// Three layers, and a token belongs to exactly one of them.
///
/// 1. `ColorScheme` — anything with a Material role.
/// 2. `ThemeExtension` — brand tokens that vary by theme and have no role.
///    `AppColors`, read as `context.colors`. Register the same set in both
///    brightnesses, or `lerp` pops instead of interpolating.
/// 3. `const` scales — invariant across themes: `AppSpacing`, `AppRadii`.
///
/// One "yes" puts a token in layer 2: does it differ between light and dark,
/// must it animate on switch, is it published across a package seam?
///
/// Caveat: `ThemeData.lerp` does not interpolate `inputDecorationTheme`, it
/// swaps it at t=0.5. Colours that must animate therefore stay out of the baked
/// theme — see [inputDecorationThemeFrom].
library;

import 'package:flutter/material.dart';

import 'extensions/colors.dart';
import 'radii.dart';

/// The brand palette, per brightness. Edit the hex here.
class _Brand {
  const _Brand({
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.error,
    required this.borderStrong,
  });

  final Color primary;

  /// Overriding `primary` alone leaves `onPrimary` derived from the seed, so
  /// the label washes out. Stated per brightness instead.
  final Color onPrimary;

  final Color secondary;
  final Color error;

  /// The one token with no Material role, so the one that reaches [AppColors].
  final Color borderStrong;
}

const _darkBrand = _Brand(
  primary: Color(0xFF7FD1B9),
  onPrimary: Color(0xFF08130F),
  secondary: Color(0xFF6CC08B),
  error: Color(0xFFE06C75),
  borderStrong: Color(0xFF262B33),
);

/// The light brand hues sit just under WCAG AA against the page (4.3:1, 3.6:1,
/// 4.5:1). Fine as fills and accents; re-check if one becomes a text colour.
const _lightBrand = _Brand(
  primary: Color(0xFF127C62),
  onPrimary: Color(0xFFFFFFFF),
  secondary: Color(0xFF2B8B57),
  error: Color(0xFFC8323E),
  borderStrong: Color(0xFFD3D9E1),
);

/// The neutral ramp behind surfaces, dividers and text. Every field has a
/// Material role, so it feeds `ColorScheme` rather than [AppColors].
class _Neutrals {
  const _Neutrals({
    required this.page,
    required this.lowest,
    required this.highest,
    required this.raised,
    required this.inset,
    required this.divider,
    required this.hairline,
    required this.ink,
    required this.inkMuted,
  });

  final Color page;
  final Color lowest;
  final Color highest;
  final Color raised;
  final Color inset;
  final Color divider;
  final Color hairline;
  final Color ink;
  final Color inkMuted;
}

const _darkNeutrals = _Neutrals(
  page: Color(0xFF0B0D10),
  lowest: Color(0xFF0D1015),
  highest: Color(0xFF39414D),
  raised: Color(0xFF0E1116),
  inset: Color(0xFF12161C),
  divider: Color(0xFF1C212A),
  hairline: Color(0xFF1E242D),
  ink: Color(0xFFDFE3E8),
  inkMuted: Color(0xFF8A919C),
);

const _lightNeutrals = _Neutrals(
  page: Color(0xFFE9ECF1),
  lowest: Color(0xFFEFF2F6),
  highest: Color(0xFFB6BDC8),
  raised: Color(0xFFF6F7F9),
  inset: Color(0xFFFFFFFF),
  divider: Color(0xFFDDE1E8),
  hairline: Color(0xFFE4E8EE),
  ink: Color(0xFF232C37),
  inkMuted: Color(0xFF6B7482),
);

ThemeData lightTheme() => _themeFrom(_lightBrand, _lightNeutrals, .light);

ThemeData darkTheme() => _themeFrom(_darkBrand, _darkNeutrals, .dark);

/// `fromSeed` fills the roles nobody has an opinion about; the stated ones are
/// then overridden from [brand] and [neutrals].
ThemeData _themeFrom(_Brand brand, _Neutrals neutrals, Brightness brightness) {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: brand.primary,
        brightness: brightness,
      ).copyWith(
        primary: brand.primary,
        onPrimary: brand.onPrimary,
        secondary: brand.secondary,
        error: brand.error,
        surface: neutrals.page,
        onSurface: neutrals.ink,
        onSurfaceVariant: neutrals.inkMuted,
        surfaceContainerLowest: neutrals.lowest,
        surfaceContainerLow: neutrals.raised,
        surfaceContainerHigh: neutrals.inset,
        surfaceContainerHighest: neutrals.highest,
        outline: neutrals.divider,
        outlineVariant: neutrals.hairline,
      );

  final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);

  return base.copyWith(
    inputDecorationTheme: inputDecorationThemeFrom(
      base.inputDecorationTheme,
      colorScheme,
    ),
    elevatedButtonTheme: _elevatedButtonTheme(colorScheme),
    // Both brightnesses go through here, so the two themes always carry the
    // same extension set.
    extensions: [AppColors(borderStrong: brand.borderStrong)],
  );
}

/// Flat, brand-filled buttons in place of M3's tonal elevated pill.
ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme scheme) =>
    ElevatedButtonThemeData(
      style:
          ElevatedButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            // `Material` runs its own 200ms animation and would trail the
            // theme; zero keeps the two in step.
            animationDuration: .zero,
            shape: const RoundedRectangleBorder(borderRadius: Radii.button),
          ).copyWith(
            // Not `styleFrom(elevation: 0)` — that still lifts to +2 on hover
            // and +6 on press.
            elevation: const WidgetStatePropertyAll(0),
          ),
    );

/// Shape and metrics shared by every field, independent of brightness.
const _inputShape = OutlineInputBorder(borderRadius: Radii.input);

/// Filled fields with a hairline border rather than Material's underline.
///
/// Takes the `ColorScheme` so the caller picks when colours resolve:
/// `ThemeData` bakes them once, `InputFormField` re-reads them per build off
/// the live theme so a border tracks a switch instead of jumping at t=0.5.
InputDecorationThemeData inputDecorationThemeFrom(
  InputDecorationThemeData theme,
  ColorScheme scheme,
) {
  final hairline = OutlineInputBorder(
    borderRadius: Radii.input,
    borderSide: BorderSide(color: scheme.outlineVariant),
  );

  return theme.copyWith(
    isDense: true,
    errorMaxLines: 10,
    filled: true,
    fillColor: scheme.surfaceContainerHigh,
    border: _inputShape,
    enabledBorder: hairline,
    disabledBorder: hairline,
    focusColor: scheme.primary,
  );
}
