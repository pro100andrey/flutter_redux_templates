import 'dart:developer';
import 'package:logging/logging.dart';

void setupRootLogger({bool isDebugMode = true}) {
  // only enable logging for debug mode
  Logger.root.level = isDebugMode ? Level.ALL : Level.OFF;
  hierarchicalLoggingEnabled = true;

  Logger.root.onRecord.listen((rec) {
    if (!isDebugMode) {
      return;
    }

    const endColor = '\x1b[0m';
    const whiteColor = '\x1b[37m';
    const grayColor = '\x1b[90m';
    const infoColor = '\x1b[94m';
    const warningColor = '\x1b[93m';
    const severeColor = '\x1b[103m\x1b[31m';
    const shoutColor = '\x1b[41m\x1b[93m';
    const levelColor = '\x1b[93m';

    var startColor = grayColor;

    switch (rec.level.name) {
      case 'INFO':
        startColor = infoColor;
        break;
      case 'WARNING':
        startColor = warningColor;
        break;
      case 'SEVERE':
        startColor = severeColor;
        break;
      case 'SHOUT':
        startColor = shoutColor;
        break;
    }

    final time = rec.time;
    final level = rec.level.name;
    final message = rec.message;
    final logger = rec.loggerName;

    final fullMessage = '$whiteColor$time$endColor '
        '$levelColor$level$endColor '
        '$startColor$message$endColor';

    const kIsWeb = identical(0, 0.0);

    if (!kIsWeb) {
      log(
        fullMessage,
        time: time,
        name: logger,
      );
    } else {
      // ignore: avoid_print
      print('[$logger] $fullMessage');
    }
  });
}
