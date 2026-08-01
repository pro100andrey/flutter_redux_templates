import 'package:flutter/material.dart';

import '../theme/radii.dart';
import '../theme/spacing.dart';

/// The app's action button, in the four roles the app uses.
///
/// Named constructors rather than optional colours, so a caller picks a role
/// and cannot invent a fifth style.
class Button extends StatelessWidget {
  /// Solid accent fill — the one affirmative action on a screen.
  const Button.primary({
    required this.label,
    required this.onPressed,
    this.expand = false,
    super.key,
  }) : _variant = .primary;

  /// Muted fill with a hairline border — supporting actions.
  const Button.secondary({
    required this.label,
    required this.onPressed,
    this.expand = false,
    super.key,
  }) : _variant = .secondary;

  /// No fill, no border — inline links such as "forgot password".
  const Button.text({
    required this.label,
    required this.onPressed,
    this.expand = false,
    super.key,
  }) : _variant = .text;

  /// Drawn entirely in the error colour — destructive actions.
  const Button.danger({
    required this.label,
    required this.onPressed,
    this.expand = false,
    super.key,
  }) : _variant = .danger;

  final String label;

  /// Null disables the button; the theme dims it.
  final VoidCallback? onPressed;

  /// Stretch to the available width instead of hugging.
  final bool expand;

  final _Variant _variant;

  static const double _height = 48;
  static const double _minWidth = 200;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const shape = RoundedRectangleBorder(borderRadius: Radii.button);

    final (background, foreground, border) = switch (_variant) {
      .primary => (scheme.primary, scheme.onPrimary, null),
      .secondary => (
        scheme.surfaceContainerHigh,
        scheme.onSurface,
        scheme.outline,
      ),
      .text => (Colors.transparent, scheme.primary, null),
      .danger => (
        Colors.transparent,
        scheme.error,
        scheme.error.withValues(alpha: 0.4),
      ),
    };

    // A TextButton, not a filled button with a transparent fill: Material
    // sizes and pads it for inline use, so hover tints the words rather than
    // a slab the size of a primary action.
    if (_variant == .text) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          shape: shape,
          minimumSize: expand ? const Size(double.infinity, _height) : null,
        ),
        child: Text(label),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style:
          ElevatedButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            minimumSize: Size(expand ? .infinity : _minWidth, _height),
            padding: const .symmetric(horizontal: AppSpacing.md),
            shape: border == null
                ? shape
                : shape.copyWith(side: BorderSide(color: border)),
          ).copyWith(
            // NOT `styleFrom(elevation: 0)`: that expands a scalar into a
            // state map that still lifts to +2 on hover and +6 on press, so
            // the button grows a shadow the moment the mouse touches it.
            elevation: const WidgetStatePropertyAll(0),
          ),
      child: Text(label),
    );
  }
}

enum _Variant { primary, secondary, text, danger }
