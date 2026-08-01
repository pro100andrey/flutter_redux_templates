import 'dart:io';

import 'package:tools/src/command_runner.dart';

Future<void> main(List<String> args) async {
  final code = await FrxRunner().runFrx(args);
  await stdout.flush();
  exit(code);
}
