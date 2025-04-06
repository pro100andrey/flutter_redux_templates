import 'package:flutter/material.dart';

typedef ContextGetter = BuildContext? Function();

class StyledSnackbar {
  StyledSnackbar._();

  static final StyledSnackbar instance = StyledSnackbar._();

  ContextGetter? contextGetter;

  void show({
    required String message,
    BuildContext? context,
    String? title,
    double maxWidth = 400,
  }) {
    final ctx = context ?? contextGetter?.call();

    if (ctx == null) {
      return;
    }

    final additional = MediaQuery.of(ctx).size.width - maxWidth;
    final inset = (additional > 0 ? additional / 2 : 32).toDouble();
    final left = inset;
    final right = inset;

    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        elevation: 6,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(left, 0, right, 32),
        backgroundColor: Colors.black26,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title,
                style: Theme.of(
                  ctx,
                ).textTheme.bodyLarge!.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 22),
            ],
            Text(
              message,
              style: Theme.of(
                ctx,
              ).textTheme.bodyMedium!.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
