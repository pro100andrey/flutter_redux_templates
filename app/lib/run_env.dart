import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/dependencies.dart';
import 'package:business/environment.dart';
import 'package:business/redux/store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pro_pretty_logging/pro_pretty_logging.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'navigation/app_router.dart';

bool get isDesktop =>
    [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ].contains(defaultTargetPlatform) &&
    !kIsWeb;

Future<void> runEnv(Environment env) async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarBrightness: Brightness.dark,
    ),
  );

  prettyLogging(enable: kDebugMode);

  final store = await createStore(env);

  await (store.dependencies! as AppDependencies).warmUp();

  final appRouter = createAppRouter(store);

  // ExceptionDialog sits above the router's Navigator (in the MaterialApp
  // builder), so its dialogs need a context *inside* the Navigator. Hand
  // async_redux the router's navigator key so it can find one.
  NavigateAction.setNavigatorKey(appRouter.navigatorKey);

  // Re-run the auth guard whenever the logged-in state flips, so login/logout
  // bounces the user to the right area — the auto_route analogue of
  // go_router's `refreshListenable`.
  final routerConfig = appRouter.config(
    reevaluateListenable: ReevaluateListenable.stream(
      store.onChange.map((state) => state.session.token != null).distinct(),
    ),
  );

  if (isDesktop) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(800, 640),
      center: true,
      minimumSize: Size(320, 640),
    );

    unawaited(
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      }),
    );
  }

  runApp(
    StoreProvider(
      store: store,
      child: AppConnector(routerConfig: routerConfig),
    ),
  );
}
