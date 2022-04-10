import 'package:business/redux/store.dart';
import 'package:flutter/material.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final store = newStore();
  runApp(App(store: store));
}
