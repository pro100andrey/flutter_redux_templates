import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:localization/localization.dart';
import 'package:routemaster/routemaster.dart';

import 'connectors/initial_page_connector.dart';

class App extends StatelessWidget {
  const App({
    required this.store,
    Key? key,
  }) : super(key: key);
  final Store<AppState> store;
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) => StoreProvider(
        store: store,
        child: MaterialApp.router(
          routerDelegate: RoutemasterDelegate(
            routesBuilder: (context) => routes,
          ),
          routeInformationParser: const RoutemasterParser(),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
        ),
      );
}

final routes = RouteMap(routes: {
  '/': (settings) => const MaterialPage<dynamic>(child: InitialPageConnector()),
});
