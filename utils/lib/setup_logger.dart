import 'dart:developer';

import 'package:logging/logging.dart';

void setupRootLogger({bool isDebugMode = false, List<String>? ignoredLoggers}) {
  if (!isDebugMode) {
    return;
  }

  // only enable logging for debug mode
  Logger.root.level = isDebugMode ? Level.ALL : Level.OFF;
  hierarchicalLoggingEnabled = true;

  Logger.root.onRecord.listen((rec) {
    if (!isDebugMode) {
      return;
    }

    if (ignoredLoggers?.toSet().contains(rec.loggerName) ?? false) {
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

    switch (rec.level) {
      case Level.INFO:
        startColor = infoColor;

      case Level.WARNING:
        startColor = warningColor;

      case Level.SEVERE:
        startColor = severeColor;

      case Level.SHOUT:
        startColor = shoutColor;
    }

    final fullMessage = '$whiteColor${rec.time}$endColor '
        '$levelColor${rec.level.name}$endColor '
        '$startColor${rec.message}$endColor';

    const kIsWeb = identical(0, 0.0);

    if (!kIsWeb) {
      log(
        fullMessage,
        time: rec.time,
        name: rec.loggerName,
        sequenceNumber: rec.sequenceNumber,
        zone: rec.zone,
        level: rec.level.value,
        error: rec.error,
        stackTrace: rec.stackTrace,
      );
    } else {
      // ignore: avoid_print
      print('[${rec.loggerName}] $fullMessage');
    }
  });
}
