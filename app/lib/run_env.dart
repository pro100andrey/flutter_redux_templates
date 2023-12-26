import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/environment.dart';
import 'package:business/redux/store.dart';
import 'package:business/service_locator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:utils/setup_logger.dart';

import 'app.dart';

Future<void> runEnv(Environment env) async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarBrightness: Brightness.dark,
    ),
  );

  setupRootLogger(
    isDebugMode: kDebugMode,
    ignoredLoggers: ['GoRouter'],
  );

  final store = newStore();

  await initLocator(store, env);

  runApp(
    StoreProvider(
      store: store,
      child: AppConnector(store: store),
    ),
  );
}
