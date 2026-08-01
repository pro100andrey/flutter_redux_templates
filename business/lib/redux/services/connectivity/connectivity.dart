import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../../common/services/interface.dart';

/// What the service needs from whoever is listening. Declared here, beside the
/// class that calls it, so the dependency points from the listener to the
/// service — this half knows nothing of Redux.
abstract class ConnectivityServiceListener {
  void onStatusChange({required bool isAvailable});
}

class ConnectivityService extends DisposableServiceInterface {
  ConnectivityService({required this._listener});

  final ConnectivityServiceListener _listener;

  var _isNetworkAvailable = true;

  bool get isNetworkAvailable => _isNetworkAvailable;

  StreamSubscription<dynamic>? _subscription;

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
      _listener.onStatusChange(isAvailable: true);
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
      _listener.onStatusChange(isAvailable: _isNetworkAvailable);
    }
  }
}
