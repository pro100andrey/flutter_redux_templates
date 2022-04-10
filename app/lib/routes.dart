import 'package:flutter/material.dart';
import 'package:routemaster/routemaster.dart';

import 'connectors/forgot_password_page_connector.dart';
import 'connectors/initial_page_connector.dart';
import 'connectors/registration_page_connector.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class Routes {
  static const initial = '/';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
}

final routemaster = RoutemasterDelegate(
  routesBuilder: (context) => RouteMap(
    routes: {
      //
      Routes.initial: (settings) => const MaterialPage<dynamic>(
            child: InitialPageConnector(),
          ),
      //
      Routes.register: (settings) => const MaterialPage<dynamic>(
            child: RegistrationPageConnector(),
          ),
      //
      Routes.forgotPassword: (_) => const MaterialPage<dynamic>(
            child: ForgotPasswordPageConnector(),
          ),
    },
  ),
);
