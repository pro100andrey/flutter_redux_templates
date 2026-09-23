import 'dart:async';

import 'package:business/redux/services/connectivity/connectivity.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// What NetworkManager's absence looks like to the plugin on Linux: the
/// one-shot check throws, and so may the stream.
class _Unanswerable implements Connectivity {
  final updates = StreamController<List<ConnectivityResult>>();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => updates.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() =>
      throw Exception('org.freedesktop.NetworkManager was not provided');

  Future<void> close() => updates.close();
}

class _Listener implements ConnectivityServiceListener {
  final heard = <bool>[];

  @override
  void onStatusChange({required bool isAvailable}) => heard.add(isAvailable);
}

/// `warmUp()` awaits `start()` before `runApp`, so whatever escapes it is an
/// app that does not open — on WSL, in a container, on any Linux desktop
/// without NetworkManager.
void main() {
  late _Unanswerable connectivity;
  late _Listener listener;
  late ConnectivityService service;

  setUp(() {
    connectivity = _Unanswerable();
    listener = _Listener();
    service = ConnectivityService(
      listener: listener,
      connectivity: connectivity,
    );
  });

  tearDown(() async {
    await service.dispose();
    await connectivity.close();
  });

  test('a status the platform cannot give is assumed online', () async {
    await expectLater(service.start(), completes);

    expect(listener.heard, [true]);
    expect(service.isNetworkAvailable, isTrue);
  });

  test('an error on the stream is not an unhandled one', () async {
    await service.start();

    // An unhandled error on the subscription fails this test through the
    // test zone, as it would end the app through the root zone.
    connectivity.updates.addError(Exception('D-Bus went away'));
    await pumpEventQueue();

    connectivity.updates.add([ConnectivityResult.none]);
    await pumpEventQueue();

    expect(listener.heard.last, isFalse, reason: 'and it keeps listening');
  });
}
