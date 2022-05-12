import 'package:business/redux/store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:utils/setup_logger.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupRootLogger(isDebugMode: kDebugMode);

  final store = newStore();
  runApp(App(store: store));
}
