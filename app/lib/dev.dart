import 'package:business/environment.dart';

import 'run_env.dart';

Future<void> main() async => runEnv(await Environment.dev());
