import 'package:flutter/material.dart';

import '../theme/radii.dart';
import '../theme/spacing.dart';

/// The app's card treatment: a raised surface with a hairline border.
///
/// Sits on `surfaceContainerLow`, a step below the `surfaceContainerHigh` that
/// inputs fill with, so nested fields read as the lighter of the two.
///
/// Width-agnostic — the layout that places the card decides how wide it is.
class AppCard extends StatelessWidget {
  const AppCard({required this.child, this.padding = Insets.lg, super.key});

  final Widget child;

  /// Room around the content. [Insets.md] for denser cards.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: Radii.card,
        border: .all(color: scheme.outline),
      ),
      child: child,
    );
  }
}
