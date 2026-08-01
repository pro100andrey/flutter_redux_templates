import 'package:flutter/material.dart';

import '../theme/spacing.dart';
import 'app_card.dart';

/// The page an auth form sits on: a titled [AppCard] in a width-capped column
/// that centres on any screen and scrolls when it has to.
class AuthFormContainer extends StatelessWidget {
  const AuthFormContainer({
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
    this.maxWidth = _maxWidth,
    super.key,
  });

  final String title;

  /// One line under [title] saying what the screen is for.
  final String? subtitle;

  final List<Widget> children;

  /// Sits above the card, aligned to its right edge.
  final Widget? trailing;

  /// How wide the card may grow before it stops and centres.
  final double maxWidth;

  static const double _maxWidth = 340;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: Insets.md,
      // Centre the width-capped card. Scaffold hands down *loose* width, so
      // without this the scroll view shrink-wraps and sticks to the left on
      // web/desktop/tablet.
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: .end,
            mainAxisSize: .min,
            children: [
              // In the column rather than pinned to the corner: a `Positioned`
              // at the same inset as the card's own top edge lands on top of
              // it once the card fills a narrow screen.
              if (trailing != null) ...[trailing!, Gaps.md],
              AppCard(
                child: _Content(
                  title: title,
                  subtitle: subtitle,
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Heading, optional subtitle, then the form.
class _Content extends StatelessWidget {
  const _Content({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        if (subtitle != null) ...[
          Gaps.xs,
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        ...children,
      ],
    );
  }
}
