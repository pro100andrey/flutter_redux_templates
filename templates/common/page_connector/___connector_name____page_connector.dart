import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../ui/pages/___connector_name____page.dart';

class ___ConnectorName___PageConnector extends StatelessWidget {
  const ___ConnectorName___PageConnector({
    Key? key,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) =>
      StoreConnector<AppState, ____ConnectorName___PageVm>(
        debug: this,
        vm: () => _Factory(this),
        builder: (context, vm) => ___ConnectorName___Page(
          vm: ___ConnectorName___PageVm(
            isWaiting: vm.isWaiting,
          ),
        ),
      );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ___ConnectorName___PageConnector> {
  _Factory(___ConnectorName___PageConnector widget) : super(widget);
  @override
  ____ConnectorName___PageVm fromStore() => ____ConnectorName___PageVm(
        isWaiting: false,
      );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class ____ConnectorName___PageVm extends Vm with EquatableMixin {
  ____ConnectorName___PageVm({
    required this.isWaiting,
  });

  final bool isWaiting;

  @override
  List<Object?> get props => [isWaiting];
}
