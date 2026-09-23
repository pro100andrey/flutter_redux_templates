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
  /// [connectivity] is the plugin, and a parameter only so a test can hand in
  /// one that fails — `Connectivity()` is a singleton over a platform channel.
  ConnectivityService({
    required this._listener,
    Connectivity? connectivity,
  }) : _connectivity = connectivity ?? Connectivity();

  final ConnectivityServiceListener _listener;
  final Connectivity _connectivity;

  var _isNetworkAvailable = true;

  bool get isNetworkAvailable => _isNetworkAvailable;

  StreamSubscription<dynamic>? _subscription;

  /// Subscribes, then asks once for the current status.
  ///
  /// **A platform that cannot answer means online, not a crash.** On Linux the
  /// plugin asks NetworkManager over D-Bus, and where there is none — WSL, a
  /// container, a minimal desktop — `checkConnectivity()` throws. `warmUp()`
  /// awaits this before `runApp`, so that exception used to end the launch:
  /// the app would not start on a machine that was, in fact, online. Assuming
  /// the network is there costs at most a request that fails the ordinary way;
  /// assuming it is not would paint the no-internet overlay over a working
  /// app. A stream that errors later is logged for the same reason — an
  /// unhandled error on it reaches the zone and ends the app just the same.
  @override
  Future<void> start() async {
    super.start();

    if (kIsWeb) {
      _listener.onStatusChange(isAvailable: true);
      return;
    }

    _subscription = _connectivity.onConnectivityChanged.listen(
      _setNetworkStatus,
      onError: (Object error, StackTrace stackTrace) => logger.warning(
        'Connectivity updates failed; keeping the last known status',
        error,
        stackTrace,
      ),
    );

    try {
      _setNetworkStatus(await _connectivity.checkConnectivity());
    } on Object catch (error, stackTrace) {
      logger.warning(
        'Connectivity status unavailable; assuming online',
        error,
        stackTrace,
      );
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
