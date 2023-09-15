import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:localization/localization.dart';
import 'package:ui/theme/common.dart';

import 'connectors/top_level_page_connector.dart';
import 'navigation/routers_flow.dart';
import 'navigation/routes.dart';

class AppConnector extends StatefulWidget {
  const AppConnector({
    required this.store,
    super.key,
  });

  final Store<AppState> store;

  @override
  State<AppConnector> createState() => _AppConnectorState();
}

class _AppConnectorState extends State<AppConnector> {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
        debug: this,
        vm: () => _Factory(widget),
        builder: (context, vm) {
          final routersMap = RoutersMap.instance;

          final router = routersMap.routerForFlow(vm.flow);

          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerDelegate: router.routerDelegate,
            routeInformationProvider: router.routeInformationProvider,
            theme: buildTheme(),
            routeInformationParser: router.routeInformationParser,
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: S.delegate.supportedLocales,
            builder: (context, child) => TopLevelPageConnector(child: child),
          );
        },
      );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends BaseFactory<AppConnector, _Vm> {
  _Factory(super.connector);

  @override
  _Vm fromStore() => _Vm(
        flow: const AuthFlow(
          redirection: AuthFlowRedirection.login,
        ),
      );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm with EquatableMixin {
  _Vm({
    required this.flow,
  });

  final RoutersFlow flow;

  @override
  List<Object?> get props => [flow];
}
