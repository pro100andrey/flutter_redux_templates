import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/pages/___connector_name____page.dart';

class ___ConnectorName___PageConnector extends StatelessWidget {
  const ___ConnectorName___PageConnector({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
        debug: this,
        vm: () => _Factory(this),
        builder: (context, vm) => ___ConnectorName___Page(
          isWaiting: vm.isWaiting,
        ),
      );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ___ConnectorName___PageConnector> {
  _Factory(___ConnectorName___PageConnector widget) : super(widget);

  @override
  _Vm fromStore() => _Vm(
        isWaiting: false,
      );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm with EquatableMixin {
  _Vm({
    required this.isWaiting,
  });

  final bool isWaiting;

  @override
  List<Object?> get props => [isWaiting];
}
