import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui/pages/splash_page.dart';

import '../connectors/forgot_password_page_connector.dart';
import '../connectors/log_in_page_connector.dart';
import '../connectors/registration_page_connector.dart';
import '../connectors/reset_password_page_connector.dart';
import '../dialogs/exception_dialog.dart';
import 'routers_flow.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class Routes {
  static const initial = 'initial';
  static const splash = 'splash';
  static const home = 'home';
  static const login = 'login';
  static const registration = 'registration';
  static const forgotPassword = 'forgotPassword';
}

GoRouter get router => RoutersMap.instance._currentRouterMap;

class RoutersMap {
  RoutersMap._();

  static final RoutersMap instance = RoutersMap._();

  late GoRouter _currentRouterMap;
  RoutersFlow? _currentFlow;

  BuildContext? get currentContext =>
      _currentRouterMap.routerDelegate.navigatorKey.currentContext;

  GoRouter routerForFlow(RoutersFlow flow) {
    if (_currentFlow == flow) {
      return _currentRouterMap;
    }

    _currentFlow = flow;

    if (flow is AuthFlow) {
      _currentRouterMap = _authRouter;
    }
    if (flow is SplashFlow) {
      _currentRouterMap = _splashRouter;
    } else {
      throw Exception('Unknown flow');
    }

    return _currentRouterMap;
  }

  GoRouter get _splashRouter => GoRouter(
        initialLocation: '/splash',
        routes: [
          GoRoute(
            path: '/splash',
            pageBuilder: (context, state) => MaterialPage<void>(
              key: state.pageKey,
              child: const ExceptionDialog<AppState>(child: SplashPage()),
            ),
          ),
        ],
      );

  GoRouter get _authRouter => GoRouter(
        initialLocation: '/login',
        redirect: (context, state) {
          final flow = _currentFlow! as AuthFlow;

          switch (flow.redirection) {
            case AuthFlowRedirection.login:
              return null;
            case AuthFlowRedirection.resetPassword:
              return '/login/reset-password';
            case AuthFlowRedirection.createPassword:
              return '/login/create-password';
          }
        },
        routes: [
          GoRoute(
            name: Routes.login,
            path: '/login',
            builder: (context, state) => const ExceptionDialog<AppState>(
              child: LogInPageConnector(),
            ),
            routes: [
              GoRoute(
                name: Routes.registration,
                path: 'registration',
                pageBuilder: (context, state) => MaterialPage<void>(
                  key: state.pageKey,
                  child: const RegistrationPageConnector(),
                ),
              ),
              GoRoute(
                name: Routes.forgotPassword,
                path: 'forgot-password',
                pageBuilder: (context, state) => MaterialPage<void>(
                  key: state.pageKey,
                  child: const ForgotPasswordPageConnector(),
                ),
              ),
              GoRoute(
                path: 'reset-password',
                pageBuilder: (context, state) => MaterialPage<void>(
                  key: state.pageKey,
                  child: const ResetPasswordPageConnector(),
                ),
              ),
            ],
          ),
        ],
      );
}
