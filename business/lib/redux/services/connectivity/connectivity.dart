import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../../common/services/interface.dart';

//
// ignore: one_member_abstracts
abstract class ConnectivityServiceDriverInterface {
  void onStatusChange({required bool isAvailable});
}

class ConnectivityService extends DisposableServiceInterface {
  ConnectivityService({required ConnectivityServiceDriverInterface driver})
    : _driver = driver;

  final ConnectivityServiceDriverInterface _driver;

  var _isNetworkAvailable = true;

  bool get isNetworkAvailable => _isNetworkAvailable;

  StreamSubscription? _subscription;

  @override
  Future<void> start() async {
    super.start();

    if (!kIsWeb) {
      _subscription = Connectivity().onConnectivityChanged.listen(
        _setNetworkStatus,
      );
      final status = await Connectivity().checkConnectivity();
      _setNetworkStatus(status);
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

  void _setNetworkStatus(List<ConnectivityResult> status) {
    final isNetworkAvailable = !status.contains(ConnectivityResult.none);

    if (_isNetworkAvailable != isNetworkAvailable) {
      _isNetworkAvailable = isNetworkAvailable;
      _driver.onStatusChange(isAvailable: _isNetworkAvailable);
    }
  }
}
