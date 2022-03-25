import 'dart:async';

import 'package:logging/logging.dart';

abstract class ServiceInterface {
  ServiceInterface() {
    init();
    setup();
  }

  void init() {
    logger.fine('init');
  }

  void setup() {
    logger.fine('setup');
  }

  late final logger = Logger(identifier);
  String get identifier => runtimeType.toString();
}

abstract class DisposableServiceInterface extends ServiceInterface {
  FutureOr<void> start() {
    logger.fine('start');
  }

  FutureOr<void> dispose() {
    logger.fine('dispose');
  }
}
