import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/environment.dart';
import 'package:business/redux/store.dart';
import 'package:business/service_locator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pro_pretty_logging/pro_pretty_logging.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

bool get isDesktop => [
  TargetPlatform.windows,
  TargetPlatform.macOS,
  TargetPlatform.linux,
].contains(defaultTargetPlatform);

Future<void> runEnv(Environment env) async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarBrightness: Brightness.dark,
    ),
  );

  prettyLogging(enable: kDebugMode, ignoredLoggers: ['GoRouter']);

  final store = newStore();

  await initLocator(store, env);

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
      child: AppConnector(store: store),
    ),
  );
}
