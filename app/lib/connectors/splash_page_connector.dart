import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:ui/pages/splash_page.dart';

/// Route target for the splash screen. Splash needs no store, so this is a thin
/// wrapper whose only job is to host `@RoutePage()` in the `app` package (the
/// dumb [SplashPage] lives in `ui` and stays routing-agnostic). The auth guard
/// bounces `/splash` straight to `/home` or `/login`.
@RoutePage()
class SplashPageConnector extends StatelessWidget {
  const SplashPageConnector({super.key});

  @override
  Widget build(BuildContext context) => const SplashPage();
}
