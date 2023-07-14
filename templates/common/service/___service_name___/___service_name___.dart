import 'dart:async';

import '../../../common/services/interface.dart';

abstract class ___ServiceName___ServiceDriverInterface {
  void onStatusChange();
  void onDispose();
}

class ___ServiceName___Service extends DisposableServiceInterface {
  ___ServiceName___Service({
    required ___ServiceName___ServiceDriverInterface driver,
  }) : _driver = driver;

  final ___ServiceName___ServiceDriverInterface _driver;

  @override
  Future<void> start() async {
    super.start();
  }

  @override
  Future<void> dispose() async {
    super.dispose();
  }
}
