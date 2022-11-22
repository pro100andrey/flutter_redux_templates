import 'dart:io';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/store.dart';
import 'package:business/service_locator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:storage/key_value_storage.dart';
import 'package:utils/setup_logger.dart';
import 'package:window_size/window_size.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHiveStorage();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    setWindowTitle('App');
    setWindowMinSize(const Size(320, 568));
  }

  setupRootLogger(isDebugMode: kDebugMode);

  final store = newStore();
  await initLocator(store);

  runApp(
    StoreProvider(
      store: store,
      child: AppConnector(store: store),
    ),
  );
}
