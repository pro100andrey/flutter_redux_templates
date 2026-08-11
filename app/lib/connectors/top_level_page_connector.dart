import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:ui/overlays/barrier_overlay.dart';
import 'package:ui/overlays/no_internet_overlay.dart';

enum _Overlay { barrier, noInternetConnection }

class TopLevelPageConnector extends StatelessWidget {
  const TopLevelPageConnector({required this.child, super.key});

  final Widget? child;

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => Stack(
      children: [
        child ?? const SizedBox.shrink(),
        if (vm.overlay == .barrier) const BarrierOverlay(),
        if (vm.overlay == .noInternetConnection) const NoInternetOverlay(),
      ],
    ),
  );
}

class _Factory extends VmFactory<AppState, TopLevelPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    _Overlay? overlay;

    if (!connectivity.isConnected) {
      overlay = .noInternetConnection;
    }

    if (isBusy) {
      overlay = .barrier;
    }

    return _Vm(overlay: overlay);
  }
}

class _Vm extends Vm {
  _Vm({this.overlay}) : super(equals: [overlay]);

  final _Overlay? overlay;
}
