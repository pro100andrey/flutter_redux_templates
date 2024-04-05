import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../../common/services/interface.dart';

// ignore: one_member_abstracts
abstract class ConnectivityServiceDriverInterface {
  void onStatusChange({
    required bool isAvailable,
  });
}

class ConnectivityService extends DisposableServiceInterface {
  ConnectivityService({
    required ConnectivityServiceDriverInterface driver,
  }) : _driver = driver;

  final ConnectivityServiceDriverInterface _driver;

  bool _isNetworkAvailable = true;

  bool get isNetworkAvailable => _isNetworkAvailable;

  StreamSubscription? _subscription;

  @override
  Future<void> start() async {
    super.start();

    if (!kIsWeb) {
      final status = await Connectivity().checkConnectivity();
      if (status.contains(ConnectivityResult.none)) {
        _setNetworkStatus(false);
      }

      _subscription = Connectivity().onConnectivityChanged.listen(
            (result) async =>
                _setNetworkStatus(!result.contains(ConnectivityResult.none)),
          );
    } else {
      _driver.onStatusChange(isAvailable: true);
    }
  }

  @override
  Future<void> dispose() async {
    super.dispose();
    await _subscription?.cancel();
    _subscription = null;
  }

  void _setNetworkStatus(bool isAvailable) {
    _isNetworkAvailable = isAvailable;
    _driver.onStatusChange(isAvailable: isAvailable);
  }
}
