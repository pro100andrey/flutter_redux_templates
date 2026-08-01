import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';

import '../connectors/forgot_password_page_connector.dart';
import '../connectors/home_page_connector.dart';
import '../connectors/log_in_page_connector.dart';
import '../connectors/registration_page_connector.dart';
import '../connectors/reset_password_page_connector.dart';
import '../connectors/splash_page_connector.dart';

part 'app_router.gr.dart';

/// The single app router instance. Assigned once by [createAppRouter].
/// Navigation goes through it — directly, or (preferred) via `GoAction`.
late final AppRouter appRouter;

/// Builds the one and only [AppRouter] and stores it in [appRouter]. The store
/// is injected so the auth guard can read the session synchronously.
AppRouter createAppRouter(Store<AppState> store) =>
    appRouter = AppRouter(store);

/// The app router. Route classes (`LogInRoute`, `HomeRoute`, …) are generated
/// into `app_router.gr.dart` from the `@RoutePage()` connectors, so adding a
/// page is: annotate a connector, add one `AutoRoute` line here, run
/// build_runner. The auth gate lives in [_AuthGuard], re-run whenever the
/// logged-in state flips (see `reevaluateListenable` in `run_env.dart`).
@AutoRouterConfig(replaceInRouteName: 'PageConnector|Page,Route')
class AppRouter extends RootStackRouter {
  AppRouter(this._store);

  final Store<AppState> _store;

  @override
  List<AutoRouteGuard> get guards => [_AuthGuard(_store)];

  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: SplashRoute.page, path: '/splash', initial: true),
    AutoRoute(page: LogInRoute.page, path: '/login'),
    AutoRoute(page: RegistrationRoute.page, path: '/registration'),
    AutoRoute(page: ForgotPasswordRoute.page, path: '/forgot-password'),
    AutoRoute(page: ResetPasswordRoute.page, path: '/reset-password'),
    AutoRoute(page: HomeRoute.page, path: '/home'),
  ];
}

/// Auth gate as a global guard — the auto_route analogue of the old go_router
/// `redirect`. Reads the session straight from the store; combined with a
/// `reevaluateListenable` on the session token, it re-runs whenever login
/// state flips, so logging in/out bounces the user to the right area.
class _AuthGuard extends AutoRouteGuard {
  const _AuthGuard(this._store);

  final Store<AppState> _store;

  /// Routes reachable while logged out. Everything else requires a session.
  static const _authArea = {
    LogInRoute.name,
    RegistrationRoute.name,
    ForgotPasswordRoute.name,
    ResetPasswordRoute.name,
  };

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final loggedIn = _store.state.session.token != null;
    final name = resolver.routeName;

    // Splash is a pure gate: bounce straight to the right area.
    if (name == SplashRoute.name) {
      resolver.redirectUntil(
        loggedIn ? const HomeRoute() : const LogInRoute(),
        replace: true,
      );
      return;
    }

    final inAuthArea = _authArea.contains(name);
    if (!loggedIn && !inAuthArea) {
      resolver.redirectUntil(const LogInRoute(), replace: true);
      return;
    }
    if (loggedIn && inAuthArea) {
      resolver.redirectUntil(const HomeRoute(), replace: true);
      return;
    }
    resolver.next();
  }
}
