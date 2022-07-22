import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/connectivity/connectivity_selectors.dart';
import 'package:business/redux/log_in/log_in_selectors.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/overlays/barrier_overlay.dart';
import 'package:ui/overlays/no_internet_overlay.dart';

enum _Overlay {
  barrier,
  noInternetConnection,
}

class TopLevelPageConnector extends StatelessWidget {
  const TopLevelPageConnector({
    required this.child,
    super.key,
  });

  final Widget? child;

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
        debug: this,
        vm: () => _Factory(this),
        builder: (context, vm) => Stack(
          children: [
            child!,
            if (vm.overlay == _Overlay.barrier) const BarrierOverlay(),
            if (vm.overlay == _Overlay.noInternetConnection)
              const NoInternetOverlay(),
          ],
        ),
      );
}

class _Factory extends VmFactory<AppState, TopLevelPageConnector> {
  _Factory(TopLevelPageConnector super.widget);

  @override
  _Vm fromStore() {
    _Overlay? overlay;

    if (!selectNetworkConnectionIsAvailable(state)) {
      overlay = _Overlay.noInternetConnection;
    }

    if (selectLogInWaiting(state)) {
      overlay = _Overlay.barrier;
    }

    return _Vm(overlay: overlay);
  }
}

class _Vm extends Vm with EquatableMixin {
  _Vm({this.overlay});

  final _Overlay? overlay;

  @override
  List<Object?> get props => [overlay];
}
