import 'package:flutter/material.dart';
import 'package:routemaster/routemaster.dart';

import 'connectors/forgot_password_page_connector.dart';
import 'connectors/initial_page_connector.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class Routes {
  static const initial = '/';
  static const forgotPassword = '/forgot-password';
}

final routemaster = RoutemasterDelegate(
  routesBuilder: (context) => RouteMap(
    routes: {
      Routes.initial: (settings) => const MaterialPage<dynamic>(
            child: InitialPageConnector(),
          ),
      Routes.forgotPassword: (_) => const MaterialPage<dynamic>(
            child: ForgotPasswordPageConnector(),
          ),
    },
  ),
);
